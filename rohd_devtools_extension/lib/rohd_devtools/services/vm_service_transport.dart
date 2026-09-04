// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_transport.dart
// VM service transport — calls ROHD via callServiceExtension/evaluate.
//
// Handles the mechanics of sending RPCs over the Dart VM service protocol:
// - Service extension fast path (~20ms) vs evaluate() fallback (~650ms)
// - Breakpoint-triggered auto-fetch with trailing-edge debounce
// - Per-signal timepoint tracking for incremental updates
// - Library discovery, string truncation recovery, address lookups
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:vm_service/vm_service.dart';

/// [RohdServiceTransport] that communicates with a running ROHD application
/// via the Dart VM service protocol.
///
/// Uses `callServiceExtension` (fast, ~20ms) when available, with
/// `evaluate()` (slower, ~650ms) as fallback.  Subscribes to debug events
/// to auto-fetch waveform data at breakpoints.
class VmServiceTransport implements RohdServiceTransport {
  VmService _vmService;
  String _isolateId;

  /// Stream controller for pushing waveform updates to listeners.
  final _updateController = StreamController<WaveformUpdateEvent>.broadcast();

  /// Subscription to VM debug events.
  StreamSubscription<Event>? _debugEventSubscription;

  /// Last simulation time we've fetched data for.
  int _lastFetchedTime = 0;

  /// Library reference for ROHD waveform service.
  LibraryRef? _waveformLibRef;

  /// Whether we're currently connected.
  bool _connected = true;

  /// Debounce timer for breakpoint-triggered fetches.
  Timer? _pauseDebounceTimer;

  /// Debounce duration for breakpoint events.
  static const _pauseDebounceDuration = Duration(milliseconds: 100);

  /// Whether ROHD-side service extensions (ext.rohd.*) are available.
  bool? _serviceExtensionsAvailable;

  /// Signal IDs and their last fetched timepoints (for selective waveform
  /// transmission).
  final _trackedSignals = <String, int>{};

  /// Address-lookup closures for compact transport.
  String? Function(String signalId)? _toAddress;
  String? Function(String addressDotString)? _fromAddress;

  /// When true, breakpoint-triggered data fetches are skipped but endTime
  /// updates are still emitted.
  bool _fetchesPaused = false;

  /// Creates a new VM service transport.
  VmServiceTransport({required VmService vmService, required String isolateId})
      : _vmService = vmService,
        _isolateId = isolateId {
    unawaited(_subscribeToDebugEvents());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RohdServiceTransport interface
  // ─────────────────────────────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  String get modeDescription => 'VM Service (Live Simulation)';

  @override
  int get lastFetchedTime => _lastFetchedTime;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updateController.stream;

  /// The signal IDs currently being tracked for auto-fetch.
  List<String> get trackedSignalKeys =>
      _trackedSignals.keys.cast<String>().toList();

  /// Whether waveform fetches are currently paused.
  bool get fetchesPaused => _fetchesPaused;

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform RPCs
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<int?> getCurrentTime() async {
    if (!_connected) {
      return null;
    }
    try {
      String? jsonStr;
      if (_serviceExtensionsAvailable ?? false) {
        jsonStr = await _callExtension('ext.rohd.currentTime');
      }
      jsonStr ??= await _evaluate('WaveformDataService.instance.currentTime');
      if (jsonStr == null) {
        return null;
      }
      final result = jsonDecode(jsonStr);
      if (result is int) {
        return result;
      }
      if (result is Map<String, dynamic> && result['currentTime'] is int) {
        return result['currentTime'] as int;
      }
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getSnapshotCompact(int time) async {
    if (!_connected) {
      return null;
    }
    try {
      String? jsonStr;
      if (_serviceExtensionsAvailable ?? false) {
        jsonStr = await _callExtension('ext.rohd.snapshotCompact', {
          'time': time.toString(),
        });
      }
      jsonStr ??= await _evaluate(
        'WaveformDataService.instance.getSnapshotCompactJSON($time)',
      );
      if (jsonStr == null) {
        return null;
      }
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  }) async {
    if (!_connected) {
      return [];
    }

    final addressesJson = jsonEncode(signalAddresses);
    final start = startTime ?? 0;
    final end = endTime ?? -1;

    String? jsonStr;
    if (_serviceExtensionsAvailable ?? false) {
      jsonStr = await _callExtension(
          'ext.rohd.waveformDataCompact',
          {
            'signalIndicesJson': addressesJson,
            'startTime': start.toString(),
            'endTime': end.toString(),
          },
          'data');
    }
    jsonStr ??= await _evaluate(
      'WaveformDataService.instance.getWaveformsCompactJSON('
      "'$addressesJson', $start, $end)",
    );
    if (jsonStr == null) {
      return [];
    }
    return _parseCompactWaveformData(jsonStr, addressToSignalId);
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async {
    if (!_connected) {
      return [];
    }

    final timepointsJson = jsonEncode(signalTimepoints);

    String? jsonStr;
    if (_serviceExtensionsAvailable ?? false) {
      jsonStr = await _callExtension(
        'ext.rohd.waveformDataWithTimepointsCompact',
        {'signalTimepointsJson': timepointsJson},
        'data',
      );
    }
    jsonStr ??= await _evaluate(
      'WaveformDataService.instance.getDataWithTimepointsCompactJSON('
      "'$timepointsJson')",
    );
    if (jsonStr == null) {
      return [];
    }
    return _parseCompactWaveformData(jsonStr, addressToSignalId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hierarchy RPCs
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getModuleTree() async {
    if (!_connected) {
      return null;
    }
    try {
      // Find the ROHD library containing ModuleServices.
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];

      LibraryRef? rohdLibRef;
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null &&
            uri.contains('rohd') &&
            (uri.contains('module_services') ||
                uri.contains('inspector_service'))) {
          rohdLibRef = libRef;
          break;
        }
      }
      rohdLibRef ??= libraries.cast<LibraryRef?>().firstWhere((libRef) {
        final uri = libRef?.uri;
        return uri != null &&
            uri.contains('rohd') &&
            uri.contains('module_tree');
      }, orElse: () => null);
      rohdLibRef ??= libraries.cast<LibraryRef?>().firstWhere((libRef) {
        final uri = libRef?.uri;
        if (uri == null) {
          return false;
        }
        final lower = uri.toLowerCase();
        return lower.contains('package:rohd') ||
            lower.contains('/packages/rohd') ||
            lower.contains('rohd.dart') ||
            lower.contains('rohd/');
      }, orElse: () => null);
      if (rohdLibRef == null) {
        debugPrint('[VmTransport] No ROHD library found');
        return null;
      }

      final result = await _vmService.evaluate(
        _isolateId,
        rohdLibRef.id!,
        'NetlistService.current?.slimJson ?? '
        'ModuleServices.instance.hierarchyJson',
      );
      if (result is InstanceRef) {
        final raw = await _getFullStringFromRef(result);
        if (raw == null) {
          return null;
        }
        return jsonDecode(raw) as Map<String, dynamic>;
      }
      return null;
    } on Exception catch (e) {
      debugPrint('[VmTransport] getModuleTree error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getModuleNetlist(String definitionName) async {
    if (!_connected) {
      return null;
    }
    try {
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];

      LibraryRef? rohdLibRef;
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null &&
            uri.contains('rohd') &&
            (uri.contains('module_services') ||
                uri.contains('inspector_service') ||
                uri.contains('module_tree'))) {
          rohdLibRef = libRef;
          break;
        }
      }
      if (rohdLibRef == null) {
        return null;
      }

      // Sanitize to prevent injection in the eval expression.
      final safeName = definitionName.replaceAll("'", r"\'");
      final expr = "NetlistService.current?.moduleJson('$safeName')";
      final result = await _vmService.evaluate(
        _isolateId,
        rohdLibRef.id!,
        expr,
      );
      if (result is InstanceRef) {
        final raw = await _getFullStringFromRef(result);
        if (raw == null || raw == 'null') {
          return null;
        }
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        // New format wraps module data under a 'modules' key.
        if (decoded.containsKey('modules') &&
            !decoded.containsKey(definitionName)) {
          return decoded['modules'] as Map<String, dynamic>;
        }
        return decoded;
      }
      return null;
    } on Exception catch (e) {
      debugPrint('[VmTransport] getModuleNetlist error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Signal tracking (for breakpoint-triggered incremental updates)
  // ─────────────────────────────────────────────────────────────────────────

  /// Start tracking a signal for auto-fetch on breakpoints.
  void trackSignal(String signalId) {
    _trackedSignals.putIfAbsent(signalId, () => -1);
  }

  /// Stop tracking a signal (timepoint retained for re-add).
  void untrackSignal(String signalId) {
    _trackedSignals.remove(signalId);
  }

  /// Stop tracking all signals.
  void untrackAllSignals() {
    _trackedSignals.clear();
  }

  /// Get the last timepoint fetched for a tracked signal.
  int getLastTrackedTimepoint(String signalId) =>
      _trackedSignals[signalId] ?? -1;

  /// Push address-lookup closures from the API layer.
  void setAddressLookups({
    required String? Function(String signalId) signalIdToAddress,
    required String? Function(String addressDotString) addressToSignalId,
  }) {
    _toAddress = signalIdToAddress;
    _fromAddress = addressToSignalId;
  }

  /// Pause waveform data fetches (endTime updates still emitted).
  void pauseFetches() {
    _fetchesPaused = true;
  }

  /// Resume waveform data fetches and pull accumulated data.
  Future<void> resumeFetches() async {
    _fetchesPaused = false;
    if (_trackedSignals.isEmpty || !_connected) {
      return;
    }

    final savedExtAvail = _serviceExtensionsAvailable;
    _serviceExtensionsAvailable = false;
    try {
      final newData = await _fetchTrackedCompact();
      if (newData.isNotEmpty) {
        for (final wf in newData) {
          if (wf.endTime != null) {
            _trackedSignals[wf.signalId] = wf.endTime!;
          }
        }
        for (final waveform in newData) {
          if (waveform.endTime != null &&
              waveform.endTime! > _lastFetchedTime) {
            _lastFetchedTime = waveform.endTime!;
          }
        }
        _updateController.add(
          WaveformUpdateEvent(
            incrementalData: newData,
            reason: WaveformUpdateReason.breakpoint,
            upToTime: _lastFetchedTime,
          ),
        );
      }
    } on Exception {
      // Failed to fetch on resume
    } finally {
      _serviceExtensionsAvailable = savedExtAvail;
    }
  }

  /// Fetch current time and emit an endTime-only update.
  Future<void> fetchAndEmitCurrentTime() async {
    final currentTime = await getCurrentTime();
    if (currentTime != null && currentTime > _lastFetchedTime) {
      _lastFetchedTime = currentTime;
      _updateController.add(
        WaveformUpdateEvent(
          incrementalData: const [],
          reason: WaveformUpdateReason.breakpoint,
          upToTime: currentTime,
        ),
      );
    }
  }

  /// Request a full garbage collection on the connected isolate.
  Future<void> requestGarbageCollection() async {
    try {
      await _vmService.getAllocationProfile(_isolateId, gc: true);
    } on Exception catch (_) {
      // Best-effort
    }
  }

  /// Swap the underlying VM service and isolate without destroying
  /// tracked-signal state.
  Future<void> reconnect(
    VmService vmService,
    String isolateId, {
    bool preserveTracking = false,
  }) async {
    await _debugEventSubscription?.cancel();
    _debugEventSubscription = null;

    _vmService = vmService;
    _isolateId = isolateId;
    _connected = true;
    _waveformLibRef = null;
    _serviceExtensionsAvailable = null;

    if (!preserveTracking) {
      _trackedSignals.clear();
    }

    unawaited(_subscribeToDebugEvents());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _connected = false;
    _pauseDebounceTimer?.cancel();
    await _debugEventSubscription?.cancel();
    await _updateController.close();
    _trackedSignals.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private: Debug events & breakpoint handling
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _subscribeToDebugEvents() async {
    try {
      await _vmService.streamListen(EventStreams.kDebug);
    } on Exception {
      // 'Stream already subscribed' is expected
    }
    try {
      _debugEventSubscription = _vmService.onDebugEvent.listen(
        _handleDebugEvent,
      );
    } on Exception {
      // Debug stream may not be available
    }
  }

  void _handleDebugEvent(Event event) {
    final kind = event.kind;
    if (kind == EventKind.kPauseBreakpoint ||
        kind == EventKind.kPauseException ||
        kind == EventKind.kPauseInterrupted ||
        kind == EventKind.kPauseExit) {
      _pauseDebounceTimer?.cancel();
      _pauseDebounceTimer = Timer(_pauseDebounceDuration, () {
        unawaited(_onPause(event));
      });
    }
  }

  Future<void> _onPause(Event event) async {
    // Service extensions can't run while paused — force evaluate() path.
    final savedExtAvail = _serviceExtensionsAvailable;
    _serviceExtensionsAvailable = false;

    try {
      if (_trackedSignals.isEmpty || _fetchesPaused) {
        final currentTime = await getCurrentTime();
        if (currentTime != null && currentTime > _lastFetchedTime) {
          _lastFetchedTime = currentTime;
          _updateController.add(
            WaveformUpdateEvent(
              incrementalData: const [],
              reason: WaveformUpdateReason.breakpoint,
              upToTime: currentTime,
            ),
          );
        }
        return;
      }

      final newData = await _fetchTrackedCompact();

      if (newData.isNotEmpty) {
        for (final wf in newData) {
          if (wf.endTime != null) {
            _trackedSignals[wf.signalId] = wf.endTime!;
          }
        }
        for (final waveform in newData) {
          if (waveform.endTime != null &&
              waveform.endTime! > _lastFetchedTime) {
            _lastFetchedTime = waveform.endTime!;
          }
        }
        _updateController.add(
          WaveformUpdateEvent(
            incrementalData: newData,
            reason: WaveformUpdateReason.breakpoint,
            upToTime: _lastFetchedTime,
          ),
        );
      } else {
        final currentTime = await getCurrentTime();
        if (currentTime != null && currentTime > _lastFetchedTime) {
          _lastFetchedTime = currentTime;
          _updateController.add(
            WaveformUpdateEvent(
              incrementalData: const [],
              reason: WaveformUpdateReason.breakpoint,
              upToTime: currentTime,
            ),
          );
        }
      }
    } on Exception {
      // Isolate paused but unable to fetch
    } finally {
      _serviceExtensionsAvailable = savedExtAvail;
    }
  }

  Future<List<WaveformData>> _fetchTrackedCompact() {
    final toAddr = _toAddress;
    final fromAddr = _fromAddress;

    if (toAddr != null && fromAddr != null) {
      final compactMap = <String, int>{};
      final addrToId = <String, String>{};
      for (final entry in _trackedSignals.entries) {
        final addr = toAddr(entry.key);
        if (addr != null) {
          compactMap[addr] = entry.value;
          addrToId[addr] = entry.key;
        }
      }
      if (compactMap.isNotEmpty) {
        return getWaveformDataWithTimepointsCompact(
          signalTimepoints: compactMap,
          addressToSignalId: addrToId,
        );
      }
    }

    // Fallback: legacy string-keyed path
    return _getWaveformDataWithTimepointsBatch(
      _trackedSignals.cast<String, int>(),
    );
  }

  /// Legacy string-keyed waveform data with per-signal timepoints.
  Future<List<WaveformData>> _getWaveformDataWithTimepointsBatch(
    Map<String, int> signalTimepoints,
  ) async {
    final timepointsJson = jsonEncode(signalTimepoints);

    String? jsonStr;
    if (_serviceExtensionsAvailable ?? false) {
      jsonStr = await _callExtension(
          'ext.rohd.waveformDataWithTimepoints',
          {
            'signalTimepointsJson': timepointsJson,
          },
          'data');
    }
    if (jsonStr == null) {
      final escapedJson =
          timepointsJson.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      final expression = 'WaveformDataService.instance'
          ".getDataWithTimepointsJSON('$escapedJson')";
      jsonStr = await _evaluate(expression);
    }
    if (jsonStr == null) {
      return [];
    }
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((e) => WaveformData.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private: VM protocol helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<LibraryRef?> _findWaveformLibrary() async {
    if (_waveformLibRef != null) {
      return _waveformLibRef;
    }
    try {
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];

      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null && uri.contains('waveform_service')) {
          _waveformLibRef = libRef;
          return libRef;
        }
      }
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null && uri.contains('inspector_service')) {
          _waveformLibRef = libRef;
          return libRef;
        }
      }
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri == null) {
          continue;
        }
        final lower = uri.toLowerCase();
        if (lower.contains('package:rohd') ||
            lower.contains('/packages/rohd') ||
            lower.contains('rohd.dart') ||
            lower.contains('rohd/')) {
          _waveformLibRef = libRef;
          return libRef;
        }
      }
    } on Exception {
      // Unable to find library
    }
    return null;
  }

  Future<String?> _evaluate(String expression) async {
    final libRef = await _findWaveformLibrary();
    if (libRef == null || libRef.id == null) {
      return null;
    }
    try {
      final result = await _vmService.evaluate(
        _isolateId,
        libRef.id!,
        expression,
      );
      if (result is InstanceRef) {
        if (result.valueAsStringIsTruncated ?? false) {
          return await _getFullString(result.id!);
        }
        return result.valueAsString;
      }
      return null;
    } on Exception catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('Undefined name') &&
          errorStr.contains('WaveformService')) {
        final value = await _evaluateOnFallbackLibrary(expression);
        return value;
      }
      return null;
    }
  }

  Future<String?> _evaluateOnFallbackLibrary(String expression) async {
    try {
      final isolate = await _vmService.getIsolate(_isolateId);
      final libs = isolate.libraries ?? [];
      LibraryRef? mainLib;
      for (final lib in libs) {
        final uri = lib.uri;
        if (uri == 'dart:main' || uri == 'dart:_main') {
          mainLib = lib;
          break;
        }
        if (mainLib == null &&
            uri != null &&
            !uri.startsWith('dart:') &&
            !uri.startsWith('package:')) {
          mainLib = lib;
        }
      }
      if (mainLib != null && mainLib.id != null) {
        final retryResult = await _vmService.evaluate(
          _isolateId,
          mainLib.id!,
          expression,
        );
        if (retryResult is InstanceRef) {
          if (retryResult.valueAsStringIsTruncated ?? false) {
            return await _getFullString(retryResult.id!);
          }
          return retryResult.valueAsString;
        }
      }
    } on Exception {
      // Silently fail retry
    }
    return null;
  }

  Future<String?> _callExtension(
    String method, [
    Map<String, String>? args,
    String? resultKey,
  ]) async {
    try {
      final response = await _vmService.callServiceExtension(
        method,
        isolateId: _isolateId,
        args: args,
      );
      final json = response.json;
      if (json == null) {
        return null;
      }
      if (resultKey != null) {
        final value = json[resultKey];
        if (value == null) {
          return null;
        }
        return jsonEncode(value);
      }
      return jsonEncode(json);
    } on Exception {
      _serviceExtensionsAvailable = false;
      return null;
    }
  }

  Future<String?> _getFullString(String objectId) async {
    try {
      final obj = await _vmService.getObject(_isolateId, objectId);
      if (obj is Instance && obj.valueAsString != null) {
        return obj.valueAsString;
      }
    } on Exception {
      return null;
    }
    return null;
  }

  /// Get full string from an InstanceRef (handles truncation).
  Future<String?> _getFullStringFromRef(InstanceRef ref) async {
    if (ref.valueAsStringIsTruncated ?? false) {
      final value = await _getFullString(ref.id!);
      return value;
    }
    return ref.valueAsString;
  }

  List<WaveformData> _parseCompactWaveformData(
    String jsonStr,
    Map<String, String> addressToSignalId,
  ) {
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      final result = <WaveformData>[];
      for (final item in jsonList) {
        final map = item as Map<String, dynamic>;
        final addr = map['i'] as String;
        final signalId = addressToSignalId[addr];
        if (signalId == null) {
          continue;
        }
        final rawData = map['d'] as List<dynamic>;
        final dataPoints = rawData.map((d) {
          final dp = d as Map<String, dynamic>;
          return Data(time: dp['t'] as int, value: dp['v'].toString());
        }).toList();
        result.add(WaveformData(signalId: signalId, data: dataPoints));
      }
      return result;
    } on Exception {
      return [];
    }
  }
}
