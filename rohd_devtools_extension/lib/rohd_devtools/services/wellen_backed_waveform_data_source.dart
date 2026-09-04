// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wellen_backed_waveform_data_source.dart
// WaveformDataSource backed by a Wellen-parsed VCD/FST/GHW file.
//
// This parallels what ROHD's WaveDumper + WaveformService do on the sim side:
// the VCD is parsed into an in-process waveform repository, and the existing
// API chain (LoopbackSignalWaveformApi → SignalWaveformRepository → UI)
// queries it exactly as it would query the remote WaveformService.
//
// When a design hierarchy (from JSON) has already been loaded, the hierarchy
// is used as the structural source of truth — richer than VCD scopes alone
// because it carries port directions, types, and connectivity.  VCD signals
// are matched to hierarchy signals by full path.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:dart_wellen/dart_wellen.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_data_source.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart'
    show BaseHierarchyAdapter, OccurrenceAddress;
import 'package:rohd_waveform/rohd_waveform.dart';

/// A waveform data source backed by a Wellen-parsed waveform file.
///
/// Acts as the local equivalent of ROHD's `WaveformService`: it holds the
/// parsed waveform data in memory and serves it through the same
/// waveform-data-source interface that the loopback API consumes.
///
/// This allows the wave viewer to treat a loaded VCD file identically to a
/// live ROHD simulation — the transport layer is hidden.
///
/// ## Usage
///
/// ```dart
/// final wellenApi = WellenSignalWaveformApi();
/// await wellenApi.loadBytes(vcdBytes, fileName: 'design.vcd');
///
/// final dataSource = WellenBackedWaveformDataSource(
///   wellenApi: wellenApi,
///   designHierarchy: existingHierarchyService,  // optional
/// );
///
/// // Plug into the existing loopback chain:
/// final api = LoopbackSignalWaveformApi(dataSource);
/// ```
class WellenBackedWaveformDataSource
    implements WaveformDataSource, RohdServiceTransport {
  /// The Wellen API that parsed the VCD/FST/GHW file.
  final WellenSignalWaveformApi _wellenApi;

  /// Optional design hierarchy (from JSON) — provides richer signal metadata
  /// than VCD scopes alone (port directions, types, connectivity).
  final HierarchyService? _designHierarchy;

  /// Cached module structure from the wellen API.
  ModuleStructure? _cachedStructure;

  /// Cached hierarchy service built from the waveform structure.
  HierarchyService? _cachedHierarchyService;

  /// Whether this data source is active.
  bool _isRunning = true;

  /// Last fetched time.
  int _lastFetchedTime = 0;

  /// Controller for update events (static files don't emit, but the
  /// interface requires it).
  final _updateController = StreamController<WaveformUpdateEvent>.broadcast();

  // ─── SignalOccurrence Dictionary & Compact Transport ───
  List<Map<String, dynamic>>? _cachedDictionary;
  Map<String, int>? _cachedIdToIndex;

  /// Optional name for display.
  final String name;

  /// Creates a waveform data source backed by a Wellen-parsed file.
  ///
  /// [wellenApi] must already have been loaded (via `loadFile` or `loadBytes`).
  /// [designHierarchy] is the hierarchy from the design JSON, if available.
  /// When provided, signals from VCD are matched to hierarchy signals so that
  /// port directions, types, and other metadata are preserved.
  WellenBackedWaveformDataSource({
    required WellenSignalWaveformApi wellenApi,
    HierarchyService? designHierarchy,
    this.name = 'VCD File',
  })  : assert(
          wellenApi.isLoaded,
          'WellenSignalWaveformApi must be loaded first',
        ),
        _wellenApi = wellenApi,
        _designHierarchy = designHierarchy;

  @override
  bool get isConnected => _isRunning && _wellenApi.isLoaded;

  @override
  String get modeDescription => 'Wellen File ($name)';

  @override
  int get lastFetchedTime => _lastFetchedTime;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updateController.stream;

  // ─────────────────────────────────────────────────────────────────────────
  // Module Structure
  // ─────────────────────────────────────────────────────────────────────────

  /// Load module structure from the Wellen API (VCD/FST/GHW file).
  ///
  /// This is used internally for signal enumeration and enrichment.
  /// Module structure is NOT served through the waveform data source
  /// interface — it reaches the UI via the rohd_hierarchy path.
  Future<ModuleStructure?> _loadStructure() async {
    if (!_isRunning) {
      return null;
    }
    if (_cachedStructure != null) {
      return _cachedStructure;
    }

    // Get the structure from Wellen (includes VCD scope tree + signals)
    final wellenStructure = await _wellenApi.getModuleStructureOnly();

    if (_designHierarchy != null) {
      _enrichWithDesignHierarchy(wellenStructure);
    }

    _cachedStructure = wellenStructure;
    _lastFetchedTime = wellenStructure.metadata.endTime;
    return wellenStructure;
  }

  /// Public accessor for the cached structure (used by the shell to
  /// push hierarchy into the cubit when loading VCD files).
  ModuleStructure? get cachedStructure => _cachedStructure;

  /// Enrich VCD-derived signals with metadata from the design hierarchy.
  ///
  /// VCD scopes provide signal names and widths, but not port directions
  /// or module types.  The design hierarchy (from JSON) has this richer
  /// metadata.  We walk the Wellen module tree and for each signal,
  /// look up the matching signal in the design hierarchy by full path.
  void _enrichWithDesignHierarchy(ModuleStructure structure) {
    structure.modules.forEach(_enrichNode);
  }

  void _enrichNode(HierarchyOccurrence node) {
    for (var i = 0; i < node.signals.length; i++) {
      final signal = node.signals[i];
      final path = signal.path();
      final designSignal = _resolveSignal(_designHierarchy, path);
      if (designSignal != null &&
          designSignal.direction != null &&
          designSignal.direction != 'inout' &&
          (signal.direction == null || signal.direction == 'inout')) {
        // Replace in-place with a Port carrying the authoritative direction.
        // The Wellen adapter creates all signals as SignalOccurrence.
        node.signals[i] = SignalOccurrence(
          name: signal.name,
          width: signal.width,
          direction: designSignal.direction,
        );
      }
    }
    node.children.forEach(_enrichNode);
  }

  HierarchyService? _getHierarchyService() {
    // Prefer the design hierarchy if available
    if (_designHierarchy != null) {
      return _designHierarchy;
    }

    if (_cachedHierarchyService != null) {
      return _cachedHierarchyService;
    }

    final structure = _cachedStructure;
    if (structure == null || structure.modules.isEmpty) {
      return null;
    }

    return _cachedHierarchyService = BaseHierarchyAdapter.fromTree(
      structure.modules.first,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform Data — selected signals are loaded from Wellen on demand
  // ─────────────────────────────────────────────────────────────────────────

  /// Reads just [signalIds] from Wellen, preserving file-backed lazy loading.
  ///
  /// In particular, Wellen's FST source retains unopened signals on disk until
  /// a viewport, CLI command, or snapshot actually asks for them.
  Future<List<WaveformData>> _loadWaveforms(
    List<String> signalIds, {
    int? startTime,
    int? endTime,
  }) async {
    if (signalIds.isEmpty || await _loadStructure() == null) {
      return const [];
    }
    final waveforms = await _wellenApi.getWaveformData(
      signalIds: signalIds,
      startTime: startTime,
      endTime: endTime,
    );
    return waveforms;
  }

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    if (!_isRunning) {
      return [];
    }
    final waveforms = await _loadWaveforms(
      signalIds,
      startTime: startTime,
      endTime: endTime,
    );
    return waveforms;
  }

  @override
  Future<List<WaveformData>> getWaveformDataSince({
    required List<String> signalIds,
    required int sinceTime,
  }) async {
    final waveforms = await _loadWaveforms(signalIds, startTime: sinceTime);
    return waveforms
        .map(
          (waveform) => WaveformData(
            signalId: waveform.signalId,
            data: waveform.data.where((data) => data.time > sinceTime).toList(),
          ),
        )
        .toList();
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepoints({
    required Map<String, int> signalTimepoints,
  }) async {
    if (!_isRunning) {
      return [];
    }
    final result = <WaveformData>[];
    for (final entry in signalTimepoints.entries) {
      final signalId = entry.key;
      final sinceTime = entry.value;
      final waveforms = await _loadWaveforms([signalId], startTime: sinceTime);
      for (final waveform in waveforms) {
        final data =
            waveform.data.where((data) => data.time > sinceTime).toList();
        if (data.isNotEmpty) {
          result.add(WaveformData(signalId: waveform.signalId, data: data));
        }
      }
    }

    return result;
  }

  @override
  Future<int?> getCurrentTime() async {
    if (!_isRunning) {
      return null;
    }
    return _lastFetchedTime;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snapshot
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time) async {
    if (!_isRunning) {
      return null;
    }
    final hierarchy = _getHierarchyService();
    final result = <String, Map<String, dynamic>>{};
    final structure = await _loadStructure();
    if (structure == null) {
      return result;
    }
    final waveforms = await _loadWaveforms(structure.allSignalIds);

    for (final waveform in waveforms) {
      final signalId = waveform.signalId;
      final data = waveform.data;

      // Binary search for value at-or-before time
      var value = 'x';
      if (data.isNotEmpty) {
        var lo = 0;
        var hi = data.length - 1;
        var res = -1;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (data[mid].time <= time) {
            res = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        if (res != -1) {
          value = data[res].value;
        }
      }

      final signal = _resolveSignal(hierarchy, signalId);
      result[signalId] = {
        'value': value,
        'name': signal?.name ?? signalId.split('/').last,
        'width': signal?.width ?? 1,
        if (signal?.direction != null) 'direction': signal!.direction,
      };
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SignalOccurrence Dictionary & Compact Transport
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>?> getSignalDictionary() async {
    if (!_isRunning) {
      return null;
    }
    if (_cachedDictionary != null) {
      return _cachedDictionary;
    }

    final hierarchy = _getHierarchyService();
    final structure = await _loadStructure();
    if (structure == null) {
      return const [];
    }

    final dict = <Map<String, dynamic>>[];
    final idToIndex = <String, int>{};
    var idx = 0;

    for (final signalId in structure.allSignalIds) {
      final signal = _resolveSignal(hierarchy, signalId);
      dict.add({
        'i': idx,
        'id': signalId,
        'name': signal?.name ?? signalId.split('/').last,
        'width': signal?.width ?? 1,
        'direction': signal?.direction ?? 'internal',
      });
      idToIndex[signalId] = idx;
      idx++;
    }

    _cachedDictionary = dict;
    _cachedIdToIndex = idToIndex;
    return dict;
  }

  @override
  Future<Map<String, dynamic>?> getSnapshotCompact(int time) async {
    if (!_isRunning) {
      return null;
    }
    await getSignalDictionary();
    if (_cachedIdToIndex == null) {
      return null;
    }

    final values = <String, String>{};
    final structure = await _loadStructure();
    if (structure == null) {
      return null;
    }
    final waveforms = await _loadWaveforms(structure.allSignalIds);

    for (final waveform in waveforms) {
      final signalId = waveform.signalId;
      final idx = _cachedIdToIndex![signalId];
      if (idx == null) {
        continue;
      }

      final data = waveform.data;
      var value = 'x';
      if (data.isNotEmpty) {
        var lo = 0;
        var hi = data.length - 1;
        var res = -1;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (data[mid].time <= time) {
            res = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        if (res != -1) {
          value = data[res].value;
        }
      }

      values[idx.toString()] = value;
    }

    return {'time': time, 'v': values};
  }

  @override
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  }) async {
    if (!_isRunning) {
      return [];
    }
    final signalIds = signalAddresses
        .map((address) => addressToSignalId[address])
        .whereType<String>()
        .toList();
    final waveforms = await _loadWaveforms(
      signalIds,
      startTime: startTime,
      endTime: endTime,
    );
    return waveforms;
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async {
    if (!_isRunning) {
      return [];
    }
    final result = <WaveformData>[];
    for (final entry in signalTimepoints.entries) {
      final addr = entry.key;
      final sinceTime = entry.value;
      final signalId = addressToSignalId[addr];
      if (signalId == null) {
        continue;
      }

      final waveforms = await _loadWaveforms([signalId], startTime: sinceTime);
      for (final waveform in waveforms) {
        final data =
            waveform.data.where((data) => data.time > sinceTime).toList();
        if (data.isNotEmpty) {
          result.add(WaveformData(signalId: waveform.signalId, data: data));
        }
      }
    }

    return result;
  }

  // ─── RohdServiceTransport hierarchy stubs (file-backed, no server) ──

  @override
  Future<Map<String, dynamic>?> getModuleTree() async => null;

  @override
  Future<Map<String, dynamic>?> getModuleNetlist(String definitionName) async =>
      null;

  /// Start serving data.
  void start() => _isRunning = true;

  /// Stop serving data.
  void stop() => _isRunning = false;

  @override
  Future<void> dispose() async {
    _isRunning = false;
    _cachedStructure = null;
    _cachedDictionary = null;
    _cachedIdToIndex = null;
    _cachedHierarchyService = null;
    await _updateController.close();
  }

  /// Resolve a signal pathname to a [SignalOccurrence] using a hierarchy
  /// service.
  static SignalOccurrence? _resolveSignal(
    HierarchyService? hs,
    String pathname,
  ) {
    if (hs == null) {
      return null;
    }
    final addr = OccurrenceAddress.tryFromPathname(pathname, hs.root);
    if (addr == null) {
      return null;
    }
    return hs.signalByAddress(addr);
  }
}
