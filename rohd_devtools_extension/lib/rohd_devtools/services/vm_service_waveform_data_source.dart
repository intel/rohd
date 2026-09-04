// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_waveform_data_source.dart
// VM service-based waveform data source for DTD/debugger connection.
// Provides live waveform data from running ROHD simulations.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_data_source.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:vm_service/vm_service.dart';

/// VM service-based waveform data source for connecting to running ROHD apps.
///
/// This connects via the Dart VM service protocol to evaluate waveform
/// retrieval expressions in the target application. It subscribes to debug
/// events to automatically fetch new waveform data when execution pauses.
///
/// ## Usage
///
/// ```dart
/// final vmService = await vmServiceConnectUri(wsUri);
/// final isolate = await vmService.getIsolate(isolateId);
///
/// final dataSource = VmServiceWaveformDataSource(
///   vmService: vmService,
///   isolateId: isolateId,
/// );
///
/// // Get initial data (compact integer-indexed transport)
/// final waveforms = await dataSource.getWaveformDataCompact(
///   signalIndices: [0, 3, 7],
///   addressToSignalId: {'0': 'top/clk', '0.3': 'top/count', '0.7': 'top/reset'},
/// );
///
/// // Listen for breakpoint-triggered updates
/// dataSource.liveUpdates?.listen((event) {
///   print('New data up to ${event.upToTime}: ${event.reason}');
/// });
/// ```
///
/// ## ROHD Integration
///
/// This requires a corresponding `WaveformDataService` in the ROHD library
/// (parallel to `ModuleTree` for hierarchy). The service should expose:
///
/// - `WaveformDataService.instance.getSignalsJSON(scopePath)` - Signal metadata
/// - `WaveformDataService.instance.getWaveformsJSON(signalIds, start, end)` -
///   Data
/// - `WaveformDataService.instance.getDataSinceJSON(signalIds, sinceTime)` -
///   Incremental
/// - `WaveformDataService.instance.currentTime` - Latest simulation time
class VmServiceWaveformDataSource implements WaveformDataSource {
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

  /// Monotonic ID for compact waveform debug logs.
  int _compactRequestSequence = 0;

  /// Debounce timer for breakpoint-triggered fetches (optimization B:
  /// trailing-edge debounce collapses rapid breakpoints into one fetch).
  Timer? _pauseDebounceTimer;

  /// Debounce duration for breakpoint events.
  /// 100ms is enough to collapse bursty breakpoints while staying responsive.
  static const _pauseDebounceDuration = Duration(milliseconds: 100);

  /// Whether ROHD-side service extensions (ext.rohd.*) are available.
  /// When true, we use callServiceExtension() (~20ms) instead of
  /// evaluate() (~650ms).  Probed once on first data request.
  bool? _serviceExtensionsAvailable;

  /// Signal IDs and their last fetched timepoints (for selective waveform
  /// transmission). Maps signal ID -> last timepoint sent. Enables per-signal
  /// incremental updates. When a signal is first tracked, use timepoint 0 to
  /// fetch full history. When a signal is re-tracked after removal, resume from
  /// last known timepoint.
  final Map<String, int> _trackedSignals = {};

  /// Address-lookup closures pushed from the API layer so that
  /// breakpoint-triggered fetches use address-keyed transport instead of
  /// string signal paths.
  ///
  /// When non-null, [_onPause] and [resumeFetches] call
  /// [getWaveformDataWithTimepointsCompact] instead of the legacy
  /// string-keyed [getWaveformDataWithTimepoints].
  String? Function(String signalId)? _toAddress;
  String? Function(String addressDotString)? _fromAddress;

  /// Push address-lookup closures from the API layer.
  ///
  /// Once set, all breakpoint-triggered fetches use the compact wire format.
  /// The closures perform O(depth) tree-walk conversions via
  /// the hierarchy service — no stored maps needed.
  void setAddressLookups({
    required String? Function(String signalId) signalIdToAddress,
    required String? Function(String addressDotString) addressToSignalId,
  }) {
    _toAddress = signalIdToAddress;
    _fromAddress = addressToSignalId;
  }

  /// When true, breakpoint-triggered data fetches are skipped but endTime
  /// updates are still emitted.  This lets the timeline advance (with a gray
  /// gap region) without slowing the running simulation with evaluate() calls.
  bool _fetchesPaused = false;

  /// Whether waveform fetches are currently paused.
  bool get fetchesPaused => _fetchesPaused;

  /// Creates a new VM service waveform data source.
  VmServiceWaveformDataSource({
    required VmService vmService,
    required String isolateId,
  })  : _vmService = vmService,
        _isolateId = isolateId {
    unawaited(_subscribeToDebugEvents());
  }

  /// The signal IDs currently being tracked for auto-fetch.
  List<String> get trackedSignalKeys =>
      _trackedSignals.keys.cast<String>().toList();

  @override
  bool get isConnected => _connected;

  @override
  String get modeDescription => 'VM Service (Live Simulation)';

  @override
  int get lastFetchedTime => _lastFetchedTime;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updateController.stream;

  /// Subscribe to VM debug events to detect breakpoints.
  Future<void> _subscribeToDebugEvents() async {
    try {
      await _vmService.streamListen(EventStreams.kDebug);
    } on Exception {
      // 'Stream already subscribed' is expected when the CSM subscribed
      // first — the stream is still usable.
    }

    try {
      _debugEventSubscription = _vmService.onDebugEvent.listen(
        _handleDebugEvent,
      );
    } on Exception {
      // Debug stream may not be available in all configurations
    }
  }

  /// Handle debug events - pull data on pause.
  ///
  /// Uses trailing-edge debounce: when breakpoints fire rapidly (e.g., stepping
  /// through code or bursty simulation), only the final pause triggers a
  /// fetch. This prevents redundant VM evaluate() calls.
  void _handleDebugEvent(Event event) {
    final kind = event.kind;

    // When execution pauses, debounce and fetch new waveform data
    if (kind == EventKind.kPauseBreakpoint ||
        kind == EventKind.kPauseException ||
        kind == EventKind.kPauseInterrupted ||
        kind == EventKind.kPauseExit) {
      // Cancel any pending debounce — only the latest pause matters
      _pauseDebounceTimer?.cancel();
      _pauseDebounceTimer = Timer(_pauseDebounceDuration, () {
        unawaited(_onPause(event));
      });
    }
  }

  /// Called when debugger pauses - fetch incremental waveform data for tracked
  /// signals.
  ///
  /// When [_fetchesPaused] is true, the expensive waveform data fetch is
  /// skipped but we still get the current simulation time and emit an
  /// endTime-only update so the timeline advances (with a gray gap region).
  Future<void> _onPause(Event event) async {
    // NOTE: Do NOT probe or use service extensions here.
    // Service extensions run on the isolate's event loop, which is blocked
    // while the isolate is paused at a breakpoint.  Calling them would hang
    // until the user resumes.  The evaluate() path works during pause because
    // it uses the VM debugger's expression-evaluation engine.
    // Service extension probing is handled in getModuleStructure() instead,
    // which is called outside the pause context.

    // Force evaluate() path for the duration of this pause handler,
    // even if getModuleStructure() previously set extensions to available.
    final savedExtAvail = _serviceExtensionsAvailable;
    _serviceExtensionsAvailable = false;

    try {
      if (_trackedSignals.isEmpty || _fetchesPaused) {
        // No tracked signals yet (reconnect in progress) or fetches
        // paused: skip the expensive data fetch but update endTime so
        // the timeline advances (gray gap region drawn by painters).
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
          debugPrint(
            '[WaveformDataSource] endTime updated to '
            '$currentTime ('
            '${_trackedSignals.isEmpty ? "no tracked sigs" : "paused mode"})',
          );
        }
        return;
      }

      final newData = await _fetchTrackedCompact();

      if (newData.isNotEmpty) {
        // Update per-signal timepoints based on returned data
        for (final wf in newData) {
          final endTime = wf.endTime;
          if (endTime != null) {
            _trackedSignals[wf.signalId] = endTime;
          }
        }

        // Update last fetched time from the new data
        for (final waveform in newData) {
          final endTime = waveform.endTime;
          if (endTime != null && endTime > _lastFetchedTime) {
            _lastFetchedTime = endTime;
          }
        }

        _updateController.add(
          WaveformUpdateEvent(
            incrementalData: newData,
            reason: WaveformUpdateReason.breakpoint,
            upToTime: _lastFetchedTime,
          ),
        );
        debugPrint(
          '[WaveformDataSource] endTime updated to '
          '$_lastFetchedTime (from waveform data)',
        );
      } else {
        // No new waveform data (e.g. all constant signals) but the
        // simulation time may still have advanced.  Fetch the current
        // time and emit an endTime-only update so the timeline advances.
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
          debugPrint(
            '[WaveformDataSource] endTime updated to '
            '$currentTime (from getCurrentTime, no waveform data)',
          );
        }
      }
    } on Exception {
      // Isolate paused but unable to fetch waveform data
    } finally {
      _serviceExtensionsAvailable = savedExtAvail;
    }
  }

  /// Fetch the current simulation time and emit an endTime-only update.
  ///
  /// Call this after establishing a VM connection so the timeline shows
  /// the real simulation time immediately, even before any breakpoint
  /// fires.  Also useful when the isolate is already paused at connect
  /// time (no new pause event will arrive to trigger [_onPause]).
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
      debugPrint(
        '[WaveformDataSource] endTime updated to '
        '$currentTime (initial fetch on connect)',
      );
    }
  }

  /// Pause waveform data fetches while keeping the VM connection alive.
  ///
  /// Debug event subscriptions remain active so [_onPause] still fires and
  /// emits endTime-only updates—the timeline advances but no expensive
  /// evaluate() calls are made.  Call [resumeFetches] to resume.
  void pauseFetches() {
    _fetchesPaused = true;
  }

  /// Resume waveform data fetches and immediately pull any data that
  /// accumulated while fetches were paused.
  ///
  /// If there are tracked signals and the VM is connected, this triggers
  /// an incremental fetch so the gray gap region gets replaced with real
  /// waveform data.
  Future<void> resumeFetches() async {
    _fetchesPaused = false;
    if (_trackedSignals.isEmpty || !_connected) {
      return;
    }

    // Force evaluate() — the VM may still be paused at a breakpoint.
    final savedExtAvail = _serviceExtensionsAvailable;
    _serviceExtensionsAvailable = false;

    try {
      final newData = await _fetchTrackedCompact();

      if (newData.isNotEmpty) {
        for (final wf in newData) {
          final endTime = wf.endTime;
          if (endTime != null) {
            _trackedSignals[wf.signalId] = endTime;
          }
        }
        for (final waveform in newData) {
          final endTime = waveform.endTime;
          if (endTime != null && endTime > _lastFetchedTime) {
            _lastFetchedTime = endTime;
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
      // Failed to fetch on resume — next breakpoint will try again
    } finally {
      _serviceExtensionsAvailable = savedExtAvail;
    }
  }

  /// Fetch incremental waveform data for [_trackedSignals] using the compact
  /// address-keyed transport when address lookups are available, falling back
  /// to the legacy string-keyed transport otherwise.
  Future<List<WaveformData>> _fetchTrackedCompact() {
    final toAddr = _toAddress;
    final fromAddr = _fromAddress;

    if (toAddr != null && fromAddr != null) {
      // Build temporary compact maps for this request only.
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

    // Fallback: index maps not yet available (e.g. first connect before
    // dictionary is built).
    return getWaveformDataWithTimepoints(
      signalTimepoints: _trackedSignals.cast<String, int>(),
    );
  }

  /// Find the ROHD waveform service library.
  Future<LibraryRef?> _findWaveformLibrary() async {
    if (_waveformLibRef != null) {
      return _waveformLibRef;
    }

    try {
      final isolate = await _vmService.getIsolate(_isolateId);
      final libraries = isolate.libraries ?? [];

      // First, look for a library that explicitly has 'waveform_service' in its
      // name
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null && uri.contains('waveform_service')) {
          _waveformLibRef = libRef;
          return libRef;
        }
      }

      // Fall back to inspector_service (which might import waveform_service)
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null && uri.contains('inspector_service')) {
          _waveformLibRef = libRef;
          return libRef;
        }
      }

      // Broader fallback: match any likely ROHD library (package or path
      // patterns). This helps in test harnesses where files are re-exported
      // or combined into different libraries.
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
      // Unable to find waveform library
    }
    return null;
  }

  /// Evaluate an expression in the ROHD waveform service.
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
        // Check if string is truncated - VM service truncates at ~128 chars
        if (result.valueAsStringIsTruncated ?? false) {
          return await _getFullString(result.id!);
        }
        return result.valueAsString;
      }

      // Check if result is an error response
      if (result is ErrorRef) {
        // Evaluation failed silently
      }
      return null;
    } on Exception catch (e) {
      final errorStr = e.toString();

      // Check if the error is about WaveformService not being in scope
      if (errorStr.contains('Undefined name') &&
          errorStr.contains('WaveformService')) {
        // Try to evaluate in the main/global library scope
        try {
          final isolate = await _vmService.getIsolate(_isolateId);
          final libs = isolate.libraries ?? [];

          // Look for 'dart:main' or the application's main library
          LibraryRef? mainLib;
          for (final lib in libs) {
            final uri = lib.uri;
            if (uri == 'dart:main' || uri == 'dart:_main') {
              mainLib = lib;
              break;
            }
            // Also try first non-package, non-dart library
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
      }

      // For non-WaveformService errors, log them
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Service Extension fast path (optimization F)
  // ─────────────────────────────────────────────────────────────────────────

  /// Call a ROHD service extension, returning the JSON string result.
  ///
  /// Returns `null` if the extension is not available or returns an error.
  ///
  /// When [resultKey] is provided, extracts just that key from the response
  /// JSON and re-encodes it.  This is needed because
  /// `ServiceExtensionResponse.result()` requires a JSON *object* string,
  /// so array results are wrapped in `{"data": [...]}` on the ROHD side.
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

      // Extract a specific key if requested (e.g. 'data' for array results
      // wrapped in {"data": [...]} on the ROHD side).
      if (resultKey != null) {
        final value = json[resultKey];
        if (value == null) {
          return null;
        }
        return jsonEncode(value);
      }

      // Default: re-encode the entire response map.
      return jsonEncode(json);
    } on Exception {
      // Mark extensions as unavailable so we fall back for future calls
      _serviceExtensionsAvailable = false;
      return null;
    }
  }

  /// Fetch the full string value when VM service truncates it.
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

  /// Request a full garbage collection on the connected isolate.
  ///
  /// This triggers `getAllocationProfile(gc: true)` which forces a major GC.
  /// Intended to be called once after initial dictionary/structure loading
  /// to clean up allocation debris before waveform data starts flowing.
  Future<void> requestGarbageCollection() async {
    try {
      await _vmService.getAllocationProfile(_isolateId, gc: true);
    } on Exception catch (_) {
      // GC request is best-effort; ignore failures
    }
  }

  // ── Legacy string-path stubs (interface obligation) ───────────────────
  // These exist only to satisfy the abstract WaveformDataSource contract.
  // The VM data source always uses the compact integer-indexed transport
  // (getWaveformDataCompact / getWaveformDataWithTimepointsCompact).

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async =>
      const [];

  @override
  Future<List<WaveformData>> getWaveformDataSince({
    required List<String> signalIds,
    required int sinceTime,
  }) async =>
      const [];

  /// Fetch waveform data using per-signal timepoints for selective
  /// transmission.
  ///
  /// This method enables handshaking which signals are being displayed in
  /// DevTools. Each signal can have a different last-fetched timepoint,
  /// allowing:
  /// - Reduced bandwidth: only displayed signals are queried
  /// - Graceful add/remove: new signals fetch from timepoint 0, removed signals
  ///   resume from their last timepoint if re-added
  /// - Per-signal incremental updates: each signal advances independently
  ///
  /// [signalTimepoints] is a `Map<SignalId, LastTimepoint>` tracking the last
  /// timepoint sent to DevTools for each signal.
  @override
  Future<List<WaveformData>> getWaveformDataWithTimepoints({
    required Map<String, int> signalTimepoints,
  }) async {
    if (signalTimepoints.isEmpty) {
      return [];
    }

    // Batch signals to avoid massive VM service expressions
    const batchSize = 50;
    final allResults = <WaveformData>[];
    final signalIds = signalTimepoints.keys.toList();

    for (var i = 0; i < signalIds.length; i += batchSize) {
      final batchSignalIds = signalIds.sublist(
        i,
        (i + batchSize < signalIds.length) ? i + batchSize : signalIds.length,
      );

      // Build timepoint map for this batch
      final batchTimepoints = <String, int>{};
      for (final signalId in batchSignalIds) {
        batchTimepoints[signalId] = signalTimepoints[signalId]!;
      }

      final batchResults = await _getWaveformDataWithTimepointsBatch(
        batchTimepoints,
      );
      allResults.addAll(batchResults);
    }

    // Update global last fetched time for reference
    for (final waveform in allResults) {
      if (waveform.endTime != null && waveform.endTime! > _lastFetchedTime) {
        _lastFetchedTime = waveform.endTime!;
      }
    }

    return allResults;
  }

  /// Internal helper to fetch waveform data for a batch with per-signal
  /// timepoints.
  Future<List<WaveformData>> _getWaveformDataWithTimepointsBatch(
    Map<String, int> signalTimepoints,
  ) async {
    final timepointsJson = jsonEncode(signalTimepoints);

    // Try service extension fast path first
    String? jsonStr;
    if (_serviceExtensionsAvailable ?? false) {
      jsonStr = await _callExtension(
          'ext.rohd.waveformDataWithTimepoints',
          {
            'signalTimepointsJson': timepointsJson,
          },
          'data');
    }

    // Fallback to evaluate()
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

  /// Stop tracking a signal for auto-fetch.
  /// Note: The last fetched timepoint is retained; if the signal is re-tracked,
  /// it will resume from this timepoint.
  void untrackSignal(String signalId) {
    _trackedSignals.remove(signalId);
  }

  /// Explicitly start tracking a signal for auto-fetch on breakpoints.
  ///
  /// If the signal is already tracked, its timepoint is preserved.
  /// If not, it starts with timepoint -1 to capture full history
  /// (ROHD filters with `c.time > sinceTime`, so -1 ensures time-0
  /// data is included).
  void trackSignal(String signalId) {
    _trackedSignals.putIfAbsent(signalId, () => -1);
  }

  /// Stop tracking all signals.
  /// Note: Timepoints are cleared; signals must be re-added to track again.
  void untrackAllSignals() {
    _trackedSignals.clear();
  }

  /// Get the last timepoint fetched for a tracked signal.
  /// Returns -1 if signal is not tracked or is newly added.
  int getLastTrackedTimepoint(String signalId) =>
      _trackedSignals[signalId] ?? -1;

  /// Get the current simulation endpoint time.
  ///
  /// Calls the ROHD-side WaveformService.currentTime to get the latest
  /// simulation time. This can be polled periodically to monitor progress.
  ///
  /// Uses service extension if available (~16ms), falls back to evaluate()
  /// (~450ms) if extensions are not yet available.
  ///
  /// Returns the current simulation time, or null if unavailable.
  @override
  Future<int?> getCurrentTime() async {
    if (!_connected) {
      return null;
    }

    try {
      // Try service extension first (if we've already probed and found it
      // available)
      String? jsonStr;
      if (_serviceExtensionsAvailable ?? false) {
        jsonStr = await _callExtension('ext.rohd.currentTime');
      } else {
        jsonStr = null;
      }

      // Fall back to evaluate() if extension not available
      jsonStr ??= await _evaluate('WaveformDataService.instance.currentTime');

      if (jsonStr == null) {
        return null;
      }

      // Parse the result - may be a bare integer (evaluate path)
      // or {"currentTime": <int>} (service extension path).
      final result = jsonDecode(jsonStr);
      if (result is int) {
        return result;
      }
      if (result is Map<String, dynamic> && result['currentTime'] is int) {
        return result['currentTime'] as int;
      }

      return null;
    } on Exception {
      // Unable to get current time
      return null;
    }
  }

  // String-keyed getSnapshot() removed — was dead code.
  // The compact path (getSnapshotCompact) is the only active snapshot
  // endpoint; the VmServiceSignalWaveformApi never calls getSnapshot().
  @override
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time) async =>
      throw UnimplementedError(
        'Use getSnapshotCompact() instead — string-keyed snapshot removed',
      );

  // Server-side getSignalDictionaryJSON() removed — dictionary is derived
  // locally from the HierarchyOccurrence tree in ModuleStructure.
  @override
  Future<List<Map<String, dynamic>>?> getSignalDictionary() async =>
      throw UnimplementedError(
        'Dictionary is derived locally from ModuleStructure',
      );

  /// Get a compact snapshot: integer-keyed values only.
  ///
  /// Uses `ext.rohd.snapshotCompact` (fast path) or falls back to
  /// `evaluate('WaveformDataService.instance.getSnapshotCompactJSON(time)')`.
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

  /// Get compact waveform data using address strings.
  ///
  /// Uses `ext.rohd.waveformDataCompact` (fast path) or falls back to
  /// `evaluate('WaveformDataService.instance.getWaveformsCompactJSON(...)')`.
  @override
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  }) async {
    final requestId = ++_compactRequestSequence;
    if (!_connected) {
      debugPrint(
        '[VmWaveform][$requestId] compact request skipped: disconnected',
      );
      return [];
    }

    final addressesJson = jsonEncode(signalAddresses);
    final start = startTime ?? 0;
    final end = endTime ?? -1;

    debugPrint(
      '[VmWaveform][$requestId] compact request: '
      '${signalAddresses.length} addresses, range=$start..$end, '
      'extensions=${_serviceExtensionsAvailable ?? "unknown"}, '
      'sample=${signalAddresses.take(5).join(", ")}',
    );

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
      debugPrint(
        '[VmWaveform][$requestId] extension compact response: '
        '${jsonStr == null ? "null" : "${jsonStr.length} chars"}',
      );
    }

    jsonStr ??= await _evaluate(
      'WaveformDataService.instance.getWaveformsCompactJSON('
      "'$addressesJson', $start, $end)",
    );

    if (jsonStr == null) {
      debugPrint('[VmWaveform][$requestId] compact response is null');
      return [];
    }

    final parsed = _parseCompactWaveformData(jsonStr, addressToSignalId);
    final pointCount = parsed.fold<int>(
      0,
      (total, waveform) => total + waveform.data.length,
    );
    debugPrint(
      '[VmWaveform][$requestId] compact parsed: '
      '${parsed.length} waveforms / $pointCount points',
    );
    return parsed;
  }

  /// Get compact incremental waveform data with per-signal timepoints.
  ///
  /// Uses `ext.rohd.waveformDataWithTimepointsCompact` (fast path) or
  /// falls back to evaluate.
  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async {
    final requestId = ++_compactRequestSequence;
    if (!_connected) {
      debugPrint(
        '[VmWaveform][$requestId] compact timepoint request skipped: '
        'disconnected',
      );
      return [];
    }

    final timepointsJson = jsonEncode(signalTimepoints);

    debugPrint(
      '[VmWaveform][$requestId] compact timepoint request: '
      '${signalTimepoints.length} addresses, '
      'extensions=${_serviceExtensionsAvailable ?? "unknown"}, '
      'sample=${signalTimepoints.keys.take(5).join(", ")}',
    );

    String? jsonStr;
    if (_serviceExtensionsAvailable ?? false) {
      jsonStr = await _callExtension(
        'ext.rohd.waveformDataWithTimepointsCompact',
        {'signalTimepointsJson': timepointsJson},
        'data',
      );
      debugPrint(
        '[VmWaveform][$requestId] extension compact timepoint response: '
        '${jsonStr == null ? "null" : "${jsonStr.length} chars"}',
      );
    }

    jsonStr ??= await _evaluate(
      'WaveformDataService.instance.getDataWithTimepointsCompactJSON('
      "'$timepointsJson')",
    );

    if (jsonStr == null) {
      debugPrint(
        '[VmWaveform][$requestId] compact timepoint response is null',
      );
      return [];
    }

    final parsed = _parseCompactWaveformData(jsonStr, addressToSignalId);
    final pointCount = parsed.fold<int>(
      0,
      (total, waveform) => total + waveform.data.length,
    );
    debugPrint(
      '[VmWaveform][$requestId] compact timepoint parsed: '
      '${parsed.length} waveforms / $pointCount points',
    );
    return parsed;
  }

  /// Parse compact waveform JSON `[{"i": "0.2.4", "d": [{"t": .., "v": ..}]}]`
  /// back into [WaveformData] objects with full signal IDs.
  List<WaveformData> _parseCompactWaveformData(
    String jsonStr,
    Map<String, String> addressToSignalId,
  ) {
    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      final result = <WaveformData>[];
      var unmappedCount = 0;

      for (final item in jsonList) {
        final map = item as Map<String, dynamic>;
        final addr = map['i'] as String;
        final signalId = addressToSignalId[addr];
        if (signalId == null) {
          unmappedCount++;
          continue;
        }

        final rawData = map['d'] as List<dynamic>;
        final dataPoints = rawData.map((d) {
          final dp = d as Map<String, dynamic>;
          return Data(time: dp['t'] as int, value: dp['v'].toString());
        }).toList();

        result.add(WaveformData(signalId: signalId, data: dataPoints));
      }

      if (unmappedCount > 0) {
        debugPrint(
          '[VmWaveform] compact parse skipped $unmappedCount unmapped '
          'addresses from ${jsonList.length} rows',
        );
      }

      return result;
    } on Exception catch (e) {
      debugPrint('[VmWaveform] compact parse error: $e');
      return [];
    }
  }

  /// Swap the underlying VM service and isolate without destroying
  /// tracked-signal state.  Used by pause/resume and lightweight
  /// reconnect flows in the standalone shell.
  ///
  /// When [preserveTracking] is true (default), the tracked signal map
  /// is kept intact so an incremental pull can fetch data produced while
  /// the WebSocket was disconnected.  When false, tracking is cleared.
  Future<void> reconnect(
    VmService vmService,
    String isolateId, {
    bool preserveTracking = false,
  }) async {
    // Cancel old debug-event subscription before swapping.
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

    // Re-subscribe to debug events on the new VM service.
    unawaited(_subscribeToDebugEvents());
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _pauseDebounceTimer?.cancel();
    await _debugEventSubscription?.cancel();
    await _updateController.close();
    _trackedSignals.clear();
    // Don't dispose the VM service here - caller manages its lifecycle
  }
}
