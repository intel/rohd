// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// base_signal_rohd_waveform.dart
// Shared algorithm for waveform data retrieval and client-side evaluation.
//
// Extracts the common logic from VmServiceSignalWaveformApi and
// LoopbackSignalWaveformApi into a single base class.  All data access
// goes through [RohdServiceTransport], so the same algorithm works for
// VM-attached and in-process modes.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Base implementation of [SignalWaveformApi] that handles all the shared
/// algorithm: hierarchy service construction, compact snapshot expansion,
/// client-side netlist evaluation, waveform synthesis, and on-demand
/// module expansion.
///
/// Subclasses provide transport-specific behavior (e.g., signal tracking
/// for VM, stream merging for loopback).
class BaseSignalWaveformApi extends SignalWaveformApi {
  /// The transport used for all server communication.
  final RohdServiceTransport transport;

  /// Cached module structure.
  ModuleStructure? _cachedStructure;

  /// Cached waveform data by signal ID.
  final _waveformCache = <String, WaveformData>{};

  /// Monotonic ID for correlating waveform request debug output.
  int _waveformRequestSequence = 0;

  /// Cached [HierarchyService] for pathname ↔ address conversion.
  HierarchyService? _hierarchyService;

  /// Guard against recursive synthesis.
  bool _inSynthesis = false;

  /// Shared cross-call cache for [evaluateSignalOnDemand].
  EvalOnDemandCache? evalCache;

  /// Netlist module definitions for client-side signal evaluation.
  Map<String, dynamic>? get schematicModules => _schematicModules;
  set schematicModules(Map<String, dynamic>? value) {
    if (!identical(value, _schematicModules)) {
      _schematicModules = value;
      _evaluator = null;
    }
  }

  Map<String, dynamic>? _schematicModules;

  /// Callback to fetch the full (non-slim) module data for a definition.
  Future<Map<String, dynamic>?> Function(String definitionName)?
      fetchModuleSchematic;

  /// Shared evaluator instance (from the shell).
  NetlistEvaluator? sharedEvaluator;

  /// Lazily-built client-side netlist evaluator.
  NetlistEvaluator? _evaluator;

  /// Definition names that have already been expanded.
  final Set<String> _expandedModules = {};

  /// In-flight module expansion futures.
  final Map<String, Future<Map<String, dynamic>?>> _inFlightExpansions = {};

  /// Creates a new base waveform API backed by [transport].
  BaseSignalWaveformApi(this.transport);

  // ─────────────────────────────────────────────────────────────────────────
  // Properties
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the transport is connected.
  bool get isConnected => transport.isConnected;

  /// Whether the API is ready to use.
  @override
  bool get isLoaded => transport.isConnected;

  /// Current simulation end time.
  int get currentEndTime => transport.lastFetchedTime;

  /// Stream of live updates from the transport.
  Stream<WaveformUpdateEvent>? get liveUpdates => transport.liveUpdates;

  /// The cached module structure.
  ModuleStructure? get cachedStructure => _cachedStructure;

  /// Whether compact transport is available.
  bool get _compactAvailable => _hierarchyService != null;

  /// All signal IDs that have been fetched.
  Set<String> get cachedSignalIds => _waveformCache.keys.cast<String>().toSet();

  // ─────────────────────────────────────────────────────────────────────────
  // Hierarchy service construction
  // ─────────────────────────────────────────────────────────────────────────

  /// Sets the module structure from the hierarchy data source.
  Future<void> setExternalStructure(ModuleStructure structure) async {
    _cachedStructure = structure;
    _hierarchyService = null;
    await _ensureIndexMaps();
  }

  /// Build the [HierarchyService] from the cached [ModuleStructure].
  Future<bool> _ensureIndexMaps() async {
    if (_hierarchyService != null) {
      return true;
    }

    final structure = _cachedStructure;
    if (structure == null || structure.modules.isEmpty) {
      debugPrint('[BaseApi] No structure available for hierarchy service');
      return false;
    }

    for (final root in structure.modules) {
      root.buildAddresses();
    }

    _hierarchyService = structure.hierarchyService ??
        BaseHierarchyAdapter.fromTree(structure.modules.first);

    final signalCount = structure.modules.fold<int>(
      0,
      (sum, r) => sum + r.signalCount,
    );
    final computedCount = structure.modules.fold<int>(
      0,
      (sum, r) => sum + r.computedSignalCount,
    );

    debugPrint(
      '[BaseApi] HierarchyService ready: '
      '$signalCount signals ($computedCount computed)',
    );
    return true;
  }

  /// Expose the hierarchy service for subclasses that need it.
  @protected
  HierarchyService? get hierarchyService => _hierarchyService;

  // ─────────────────────────────────────────────────────────────────────────
  // Core API methods
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    final requestId = ++_waveformRequestSequence;
    debugPrint(
      '[BaseApi][$requestId] getWaveformData request: '
      '${signalIds.length} signals, range=${startTime ?? "start"}..'
      '${endTime ?? "end"}, sample=${signalIds.take(5).join(", ")}',
    );

    // Partition into tracked (server-side), derivable (client-side), and
    // bit-slice (sub-field extraction from parent struct/array).
    final trackedIds = <String>[];
    final derivableIds = <String>[];
    final bitSliceIds = <String>[];

    if (_schematicModules != null && !_inSynthesis) {
      final hs = _hierarchyService;
      final eval = _getEvaluator();
      for (final id in signalIds) {
        if (isSubFieldPath(id)) {
          bitSliceIds.add(id);
          continue;
        }
        final sig = _resolveSignal(hs, id);
        if (sig != null && !sig.isComputed) {
          trackedIds.add(id);
        } else if (eval != null) {
          derivableIds.add(id);
        } else {
          trackedIds.add(id);
        }
      }
      if (derivableIds.isNotEmpty || bitSliceIds.isNotEmpty) {
        debugPrint(
          '[BaseApi] partitioned: '
          '${derivableIds.length} derivable / '
          '${bitSliceIds.length} bit-slice / '
          '${trackedIds.length} tracked of ${signalIds.length}',
        );
      }
    } else {
      for (final id in signalIds) {
        if (isSubFieldPath(id)) {
          bitSliceIds.add(id);
        } else {
          trackedIds.add(id);
        }
      }
    }

    // Fetch tracked signals from the server.
    final data = <WaveformData>[];

    if (trackedIds.isNotEmpty) {
      // Hook for subclasses to register tracked signals.
      onTrackSignals(trackedIds);

      await _ensureIndexMaps();
      final hs = _hierarchyService;
      if (_compactAvailable && hs != null) {
        final addresses = <String>[];
        final addrToId = <String, String>{};
        final skippedIds = <String>[];
        for (final id in trackedIds) {
          final addr = hs.pathnameToAddress(id)?.toDotString();
          if (addr != null) {
            addresses.add(addr);
            addrToId[addr] = id;
          } else {
            skippedIds.add(id);
            debugPrint(
              '[BaseApi][$requestId] WARNING: signal "$id" has no compact '
              'address — skipping',
            );
          }
        }
        debugPrint(
          '[BaseApi][$requestId] compact address map: '
          '${addresses.length}/${trackedIds.length} tracked resolved, '
          'skipped=${skippedIds.length}, '
          'sample=${addresses.take(5).join(", ")}',
        );
        if (addresses.isNotEmpty) {
          final fetched = await transport.getWaveformDataCompact(
            signalAddresses: addresses,
            addressToSignalId: addrToId,
            startTime: startTime,
            endTime: endTime,
          );
          final pointCount = fetched.fold<int>(
            0,
            (total, waveform) => total + waveform.data.length,
          );
          debugPrint(
            '[BaseApi][$requestId] compact transport returned '
            '${fetched.length} waveforms / $pointCount points',
          );
          data.addAll(fetched);
        } else if (trackedIds.isNotEmpty) {
          debugPrint(
            '[BaseApi][$requestId] no compact addresses resolved; '
            'no server waveform request sent',
          );
        }
      }
    }

    // Client-side synthesis for derivable + missing/empty tracked signals.
    if (_schematicModules != null && !_inSynthesis) {
      final returnedIds = data.map((wf) => wf.signalId).toSet();
      final missingOrEmpty = <String>{};
      for (final wf in data) {
        if (wf.data.isEmpty) {
          missingOrEmpty.add(wf.signalId);
        }
      }
      for (final id in trackedIds) {
        if (!returnedIds.contains(id)) {
          missingOrEmpty.add(id);
        }
      }
      if (missingOrEmpty.isNotEmpty) {
        data.removeWhere((wf) => missingOrEmpty.contains(wf.signalId));
        derivableIds.addAll(missingOrEmpty);
        debugPrint(
          '[BaseApi] ${missingOrEmpty.length} tracked signals '
          'missing/empty — retrying as derivable',
        );
      }
    }

    if (derivableIds.isNotEmpty && _schematicModules != null && !_inSynthesis) {
      final eval = _getEvaluator();
      if (eval != null) {
        for (final id in derivableIds) {
          final synth = await _synthesizeClientSide(
            eval,
            id,
            startTime: startTime,
            endTime: endTime,
          );
          if (synth != null) {
            data.add(
              WaveformData(
                signalId: synth.signalId,
                data: synth.data,
                isComputed: true,
              ),
            );
          }
        }
      }
    }

    // Bit-slice synthesis for sub-field paths (struct/array element extraction).
    if (bitSliceIds.isNotEmpty) {
      for (final id in bitSliceIds) {
        final synth = await _synthesizeBitSlice(id);
        if (synth != null) {
          data.add(synth);
        }
      }
    }

    // Update cache.
    for (final waveform in data) {
      _waveformCache[waveform.signalId] = waveform;
    }

    debugPrint(
      '[BaseApi][$requestId] getWaveformData result: '
      '${trackedIds.length} tracked + ${derivableIds.length} derived '
      '+ ${bitSliceIds.length} bit-slice '
      '=> ${data.length} waveforms',
    );

    return data;
  }

  /// Hook for subclasses to register tracked signals with the transport.
  ///
  /// Default is no-op. VmServiceSignalWaveformApi overrides this to call
  /// `transport.trackSignal()` for each ID.
  @protected
  void onTrackSignals(List<String> signalIds) {}

  @override
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) async* {
    final initialData = await getWaveformData(
      signalIds: signalIds,
      startTime: startTime,
    );
    for (final waveform in initialData) {
      yield waveform;
    }

    // Stream incremental updates from the transport.
    final updates = transport.liveUpdates;
    if (updates == null) {
      return;
    }
    await for (final update in updates) {
      for (final waveform in update.incrementalData) {
        if (signalIds.contains(waveform.signalId)) {
          // Merge with cached data.
          final cached = _waveformCache[waveform.signalId];
          if (cached != null) {
            final mergedData = [...cached.data, ...waveform.data];
            final merged = WaveformData(
              signalId: waveform.signalId,
              data: mergedData,
            );
            _waveformCache[waveform.signalId] = merged;
            yield merged;
          } else {
            _waveformCache[waveform.signalId] = waveform;
            yield waveform;
          }
        }
      }
    }
  }

  @override
  Future<int?> getCurrentTime() => transport.getCurrentTime();

  @override
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time) async {
    await _ensureIndexMaps();

    if (_compactAvailable) {
      try {
        final compact = await transport.getSnapshotCompact(time);
        if (compact != null) {
          final result = _expandCompactSnapshot(compact);
          if (result != null) {
            final computedCount =
                result.values.where((m) => m['computed'] == true).length;
            final fetchedCount = result.length - computedCount;
            final computedPercent =
                result.isNotEmpty ? (computedCount * 100 ~/ result.length) : 0;
            debugPrint(
              '[BaseApi] Snapshot(compact) at t=$time: '
              '${result.length} signals — $fetchedCount fetched, '
              '$computedCount computed ($computedPercent% local)',
            );
            return result;
          }
        }
      } on Object catch (e) {
        debugPrint('[BaseApi] Compact snapshot failed: $e');
      }
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snapshot expansion & client-side evaluation
  // ─────────────────────────────────────────────────────────────────────────

  /// Expand a compact snapshot into the full consumer format.
  Map<String, Map<String, dynamic>>? _expandCompactSnapshot(
    Map<String, dynamic> compact,
  ) {
    final values = compact['v'] as Map<String, dynamic>?;
    if (values == null) {
      return null;
    }
    final hs = _hierarchyService;

    final result = <String, Map<String, dynamic>>{};

    for (final entry in values.entries) {
      final addrStr = entry.key;
      final address = OccurrenceAddress.fromDotString(addrStr);
      final signalId = hs?.addressToPathname(address, asSignal: true);
      if (signalId == null) {
        continue;
      }

      final signal = hs?.signalByAddress(address);

      result[signalId] = {
        'value': entry.value as String,
        'name': signal?.name ?? signalId.split('/').last,
        'width': signal?.width ?? 1,
        if (signal?.direction != null) 'direction': signal!.direction,
      };
    }

    // Evaluate computed signals client-side.
    _evaluateComputedInSnapshot(result);

    // Hook for subclass diagnostics.
    onSnapshotExpanded(compact, result);

    return result;
  }

  /// Hook for subclass-specific post-expansion diagnostics.
  ///
  /// Default is a no-op. VmServiceSignalWaveformApi overrides to log
  /// parent↔child port value mismatches.
  @protected
  void onSnapshotExpanded(
    Map<String, dynamic> compact,
    Map<String, Map<String, dynamic>> result,
  ) {}

  /// Evaluate computed (server-skipped) signals using the
  /// [NetlistEvaluator].
  void _evaluateComputedInSnapshot(Map<String, Map<String, dynamic>> result) {
    final eval = _getEvaluator();
    final hs = _hierarchyService;
    if (eval == null || hs == null) {
      debugPrint(
        '[CONST-DBG] _evaluateComputedInSnapshot BAIL: '
        'eval=$eval, hs=$hs',
      );
      return;
    }

    final structure = _cachedStructure;
    if (structure == null) {
      debugPrint(
        '[CONST-DBG] _evaluateComputedInSnapshot BAIL: '
        'structure=null',
      );
      return;
    }

    // Build tracked-value map for the evaluator's snapshot lookup.
    final tracked = <String, String>{};
    for (final entry in result.entries) {
      tracked[entry.key] = entry.value['value'] as String;
    }
    String? snapshotLookup(String path) => tracked[path];

    final computedIds = <String>[];
    final computedSignals = <String, SignalOccurrence>{};
    var skipped = 0;
    final seen = <String>{...result.keys};

    void visitOccurrence(HierarchyOccurrence occ) {
      for (final signal in occ.signals) {
        final signalId = signal.path();
        if (seen.contains(signalId)) {
          continue;
        }
        if (!eval.canEvaluate(signalId)) {
          skipped++;
          continue;
        }
        computedIds.add(signalId);
        computedSignals[signalId] = signal;
        seen.add(signalId);
      }
      occ.children.forEach(visitOccurrence);
    }

    structure.modules.forEach(visitOccurrence);

    // Also discover netlist-only signals.
    final rootInstance =
        structure.modules.isNotEmpty ? structure.modules.first.path() : null;
    if (rootInstance != null) {
      final netlistPaths = eval.allEvaluablePaths(rootInstance);
      for (final path in netlistPaths) {
        if (!seen.contains(path)) {
          computedIds.add(path);
          seen.add(path);
        }
      }
    }

    // Debug: check if const_31 signals made it into computedIds
    final constDbg =
        computedIds.where((id) => id.contains('const_31')).toList();
    if (constDbg.isNotEmpty) {
      debugPrint('[CONST-DBG] const_31 signals in computedIds: $constDbg');
    } else {
      // Check if it was in 'seen' (already in result from tracked)
      final inSeen = seen.where((id) => id.contains('const_31')).toList();
      debugPrint(
        '[CONST-DBG] const_31 NOT in computedIds! '
        'inSeen=$inSeen, total computed=${computedIds.length}, '
        'skipped=$skipped',
      );
    }

    if (computedIds.isEmpty) {
      if (skipped > 0) {
        debugPrint(
          '[BaseApi] Skipped $skipped signals '
          '(unresolvable or slim modules)',
        );
      }
      return;
    }

    final resolved = eval.evaluateBatch(computedIds, snapshotLookup);

    // Debug: check what evaluateBatch returned for const_31
    final constResolved =
        resolved.entries.where((e) => e.key.contains('const_31')).toList();
    if (constResolved.isNotEmpty) {
      for (final e in constResolved) {
        debugPrint(
          '[CONST-DBG] evaluateBatch result: '
          '${e.key} => ${e.value}',
        );
      }
    } else if (constDbg.isNotEmpty) {
      debugPrint(
        '[CONST-DBG] evaluateBatch returned NOTHING for const_31! '
        'resolved.length=${resolved.length}',
      );
    }

    for (final entry in resolved.entries) {
      final signalId = entry.key;
      final signal = computedSignals[signalId];
      final width = signal?.width ?? eval.signalWidth(signalId);
      result[signalId] = {
        'value': _fmtLV(entry.value),
        'name': signal?.name ?? signalId.split('/').last,
        'width': width,
        'computed': true,
        if (signal?.direction != null) 'direction': signal!.direction,
      };
    }

    debugPrint(
      '[BaseApi] Evaluated ${resolved.length} computed signals '
      'client-side (${computedIds.length} attempted'
      '${skipped > 0 ? ', $skipped skipped' : ''})',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Client-side waveform synthesis
  // ─────────────────────────────────────────────────────────────────────────

  /// Synthesize a waveform for a computed signal by evaluating the gate
  /// graph at each timepoint of its tracked leaf dependencies.
  Future<WaveformData?> _synthesizeClientSide(
    NetlistEvaluator eval0,
    String signalId, {
    int? startTime,
    int? endTime,
  }) async {
    var eval = eval0;
    final didExpand = await ensureFullModules(signalId);
    if (didExpand) {
      _evaluator = null;
      sharedEvaluator = null;
      evalCache?.reset();
      eval = _getEvaluator()!;
    }

    // Stale cache retry.
    if (!eval.isComputed(signalId)) {
      evalCache?.reset();
      _evaluator = null;
      sharedEvaluator = null;
      eval = _getEvaluator()!;
    }

    if (!eval.isComputed(signalId)) {
      debugPrint('[ClientSynth] "$signalId": not computed in evaluator');
      final constResult = eval.evaluate(signalId, (_) => null);
      if (constResult != null && !constResult.value.contains('x')) {
        debugPrint('[ClientSynth] "$signalId": const => ${constResult.value}');
        return WaveformData(
          signalId: signalId,
          data: [Data(time: 0, value: constResult.value)],
        );
      }
      return null;
    }

    // Get signal width.
    var width = eval.signalWidth(signalId);
    final sig = _resolveSignal(_hierarchyService, signalId);
    if (sig != null) {
      width = sig.width;
    }
    if (width < 1) {
      width = 1;
    }

    // Collect tracked leaf dependencies.
    final leafIds = eval.collectLeaves(signalId);
    if (leafIds.isEmpty) {
      final r = eval.evaluate(signalId, (_) => null);
      if (r != null) {
        debugPrint('[ClientSynth] "$signalId": no leaves => ${r.value}');
        return WaveformData(
          signalId: signalId,
          data: [Data(time: 0, value: r.value)],
        );
      }
      return null;
    }

    debugPrint(
      '[ClientSynth] "$signalId": '
      '${leafIds.length} tracked leaves — fetching waveforms',
    );

    // Fetch leaf waveforms (tracked only — skip derivable partition).
    _inSynthesis = true;
    List<WaveformData> leafWaveforms;
    try {
      leafWaveforms = await getWaveformData(
        signalIds: leafIds.toList(),
        startTime: startTime,
        endTime: endTime,
      );
    } finally {
      _inSynthesis = false;
    }

    // Build leaf → time-series map and collect all timepoints.
    final leafTimeSeries = <String, List<Data>>{};
    final allTimes = <int>{};
    for (final wf in leafWaveforms) {
      leafTimeSeries[wf.signalId] = wf.data;
      for (final d in wf.data) {
        allTimes.add(d.time);
      }
    }

    if (allTimes.isEmpty) {
      debugPrint(
        '[ClientSynth] "$signalId": '
        'no timepoints from ${leafIds.length} leaves',
      );
      return WaveformData(signalId: signalId, data: const []);
    }

    final sortedTimes = allTimes.toList()..sort();

    // Initialize cursors and current snapshot.
    final cursors = <String, int>{};
    final currentSnapshot = <String, String>{};
    for (final leafId in leafIds) {
      cursors[leafId] = 0;
      final series = leafTimeSeries[leafId];
      if (series != null && series.isNotEmpty) {
        currentSnapshot[leafId] = series.first.value;
      }
    }

    String? snapshotLookup(String path) => currentSnapshot[path];

    // Fresh cache fork for time-series evaluation.
    final synthEval = NetlistEvaluator(
      _schematicModules!,
      eval.cache.withSharedStructure(),
    );

    final outputData = <Data>[];
    String? lastValue;

    for (final time in sortedTimes) {
      for (final leafId in leafIds) {
        final series = leafTimeSeries[leafId];
        if (series == null) {
          continue;
        }
        var cursor = cursors[leafId]!;
        while (cursor < series.length && series[cursor].time <= time) {
          currentSnapshot[leafId] = series[cursor].value;
          cursor++;
        }
        cursors[leafId] = cursor;
      }

      synthEval.clearValues();
      final r = synthEval.evaluate(signalId, snapshotLookup);
      final formatted = r?.value ?? ('x' * width);

      if (formatted != lastValue) {
        outputData.add(Data(time: time, value: formatted));
        lastValue = formatted;
      }
    }

    debugPrint(
      '[ClientSynth] "$signalId": '
      '${leafIds.length} leaves, ${sortedTimes.length} timepoints, '
      '${outputData.length} transitions',
    );

    return WaveformData(signalId: signalId, data: outputData);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bit-slice synthesis for struct/array sub-fields
  // ─────────────────────────────────────────────────────────────────────────

  /// Separator used to denote a sub-field path within a struct/array signal.
  ///
  /// Example: `top/counter/fp_out#mantissa` means field "mantissa" of
  /// signal `top/counter/fp_out`.  Nested: `fp_out#exponent.subfield` or
  /// array: `arr#[2]`.
  static const String subFieldSeparator = '#';

  /// Whether [signalId] refers to a sub-field of a struct/array signal.
  static bool isSubFieldPath(String signalId) =>
      signalId.contains(subFieldSeparator);

  /// Splits a sub-field path into (parentSignalPath, fieldPath).
  ///
  /// Example: `"top/counter/fp_out#mantissa"` → `("top/counter/fp_out", "mantissa")`
  /// Nested: `"top/counter/fp_out#exponent.sub"` → `("top/counter/fp_out", "exponent.sub")`
  static (String parentPath, String fieldPath) splitSubFieldPath(
    String signalId,
  ) {
    final idx = signalId.indexOf(subFieldSeparator);
    assert(idx >= 0, 'Not a sub-field path: $signalId');
    return (signalId.substring(0, idx), signalId.substring(idx + 1));
  }

  /// Resolve a sub-field path to its bit range within the parent signal.
  ///
  /// Walks the `logicType` metadata following the field path (dot-separated
  /// for nested structs, bracket-indexed for arrays).
  ///
  /// Returns `(startBit, width)` or `null` if resolution fails.
  /// Prefix used in sub-field paths to denote flat bitvector access.
  ///
  /// Examples:
  /// - `signal#b[5]` — bit 5 of the flat bitvector
  /// - `signal#b[15:8]` — bits 15 down to 8 (inclusive)
  ///
  /// Structural (array/struct) access uses no prefix:
  /// - `signal#[3]` — array element 3
  /// - `signal#fieldName` — struct field
  static const String bitvectorPrefix = 'b';

  /// Resolve sub-field bits for a bitvector or array element access.
  ({int startBit, int width})? resolveSubFieldBits(String signalId) {
    if (!isSubFieldPath(signalId)) {
      return null;
    }
    final (parentPath, fieldPath) = splitSubFieldPath(signalId);

    // Look up the parent signal's logicType metadata.
    final parentSig = _resolveSignal(_hierarchyService, parentPath);
    if (parentSig == null) {
      return null;
    }

    // Bitvector access: "b[N]" or "b[high:low]" — always flat bit extraction,
    // regardless of whether the signal is an array or struct.
    if (fieldPath.startsWith('$bitvectorPrefix[')) {
      final inner = fieldPath.substring(bitvectorPrefix.length);
      return _resolvePlainBitRange(inner, parentSig.width);
    }

    // Try structured resolution via logicType (struct/array fields).
    if (parentSig.logicType != null) {
      final resolved = _resolveFieldBits(parentSig.logicType!, fieldPath);
      if (resolved != null) {
        return resolved;
      }
    }

    // Fall back to plain bit-range extraction for [N] or [high:low].
    return _resolvePlainBitRange(fieldPath, parentSig.width);
  }

  /// Resolve a bit range from a bracket expression.
  ///
  /// Supports:
  /// - `[N]` — single bit extraction (1-bit wide at position N)
  /// - `[high:low]` — contiguous bit-range extraction (inclusive)
  static ({int startBit, int width})? _resolvePlainBitRange(
    String fieldPath,
    int parentWidth,
  ) {
    // Single bit: [N]
    final singleMatch = regExpFirstMatch(r'^\[(\d+)\]$', fieldPath);
    if (singleMatch != null) {
      final bit = int.parse(singleMatch.group(1)!);
      if (bit >= parentWidth) {
        return null;
      }
      return (startBit: bit, width: 1);
    }
    // Bit range: [high:low]
    final rangeMatch = regExpFirstMatch(r'^\[(\d+):(\d+)\]$', fieldPath);
    if (rangeMatch != null) {
      final high = int.parse(rangeMatch.group(1)!);
      final low = int.parse(rangeMatch.group(2)!);
      if (high >= parentWidth || low >= parentWidth) {
        return null;
      }
      final actualHigh = high > low ? high : low;
      final actualLow = high > low ? low : high;
      return (startBit: actualLow, width: actualHigh - actualLow + 1);
    }
    return null;
  }

  /// Recursively resolve a field path within a logicType to bit coordinates.
  static ({int startBit, int width})? _resolveFieldBits(
    Map<String, dynamic> logicType,
    String fieldPath,
  ) {
    // Split into first segment and remainder.
    final dotIdx = fieldPath.indexOf('.');
    final String segment;
    final String? remainder;
    if (dotIdx >= 0) {
      segment = fieldPath.substring(0, dotIdx);
      remainder = fieldPath.substring(dotIdx + 1);
    } else {
      segment = fieldPath;
      remainder = null;
    }

    // Struct case: look up named field.
    final fields = logicType['fields'] as List<dynamic>?;
    if (fields != null) {
      for (final fieldRaw in fields) {
        final field = fieldRaw as Map<String, dynamic>;
        final name = field['name'] as String? ?? '';
        if (name != segment) {
          continue;
        }

        final bits = field['bits'] as List<dynamic>?;
        final width = field['width'] as int? ?? 1;
        final startBit = bits != null && bits.isNotEmpty
            ? (bits.cast<int>().reduce((a, b) => a < b ? a : b))
            : 0;

        if (remainder == null) {
          return (startBit: startBit, width: width);
        }
        // Recurse into nested type.
        final nestedType = field['type'] as Map<String, dynamic>?;
        if (nestedType == null) {
          return null;
        }
        final inner = _resolveFieldBits(nestedType, remainder);
        if (inner == null) {
          return null;
        }
        return (startBit: startBit + inner.startBit, width: inner.width);
      }
      return null; // field not found
    }

    // Array case: look up by index [N].
    final arrayDims = logicType['arrayDims'] as List<dynamic>?;
    if (arrayDims != null) {
      final leafWidth = (logicType['elementWidth'] as int?) ?? 1;
      // For multi-dimensional arrays, compute the actual per-element width
      // from remaining dimensions.
      final remainingDims =
          arrayDims.length > 1 ? arrayDims.sublist(1).cast<int>() : <int>[];
      final perElementWidth = remainingDims.isEmpty
          ? leafWidth
          : remainingDims.fold<int>(leafWidth, (acc, d) => acc * d);
      final elementType = logicType['elementType'] as Map<String, dynamic>?;

      // Parse "[N]" from segment.
      final match = regExpFirstMatch(r'^\[(\d+)\]$', segment);
      if (match == null) {
        return null;
      }
      final index = int.parse(match.group(1)!);
      // Bounds check: if the index exceeds the array dimension, fall through
      // to the plain bit-range fallback (the path may represent a bit index
      // rather than an array element).
      final dim = arrayDims[0] as int;
      if (index >= dim) {
        return null;
      }
      final startBit = index * perElementWidth;

      if (remainder == null) {
        return (startBit: startBit, width: perElementWidth);
      }
      // For nested resolution: use explicit elementType if available,
      // otherwise construct a synthetic sub-type from remaining dims.
      final subType = elementType ??
          (remainingDims.isNotEmpty
              ? <String, dynamic>{
                  'arrayDims': remainingDims,
                  'elementWidth': leafWidth,
                  'width': perElementWidth,
                }
              : null);
      if (subType == null) {
        return null;
      }
      final inner = _resolveFieldBits(subType, remainder);
      if (inner == null) {
        return null;
      }
      return (startBit: startBit + inner.startBit, width: inner.width);
    }

    return null;
  }

  /// Synthesize a waveform for a sub-field by bit-slicing the parent's data.
  ///
  /// This is the "computed waveform" equivalent for struct/array fields:
  /// the parent signal is the single leaf dependency, and the evaluation is
  /// a simple bit extraction at each timepoint.
  Future<WaveformData?> _synthesizeBitSlice(
    String signalId, {
    int? startTime,
    int? endTime,
  }) async {
    final resolved = resolveSubFieldBits(signalId);
    if (resolved == null) {
      debugPrint('[BitSlice] "$signalId": cannot resolve field bits');
      return null;
    }

    final (parentPath, _) = splitSubFieldPath(signalId);
    final parentWidth =
        _resolveSignal(_hierarchyService, parentPath)?.width ?? 1;

    // Fetch the parent waveform.
    _inSynthesis = true;
    List<WaveformData> parentData;
    try {
      parentData = await getWaveformData(
        signalIds: [parentPath],
        startTime: startTime,
        endTime: endTime,
      );
    } finally {
      _inSynthesis = false;
    }

    if (parentData.isEmpty || parentData.first.data.isEmpty) {
      debugPrint('[BitSlice] "$signalId": parent has no data');
      return WaveformData(signalId: signalId, data: const []);
    }

    final pData = parentData.first.data;
    final lo = resolved.startBit;
    final hi = lo + resolved.width - 1;
    final fieldWidth = resolved.width;

    // Safety: ensure the resolved bit range fits within the parent width.
    if (hi >= parentWidth) {
      debugPrint(
        '[BitSlice] "$signalId": resolved bits [$hi:$lo] exceed '
        'parent width $parentWidth — skipping',
      );
      return WaveformData(signalId: signalId, data: const []);
    }

    // Extract bits at each parent timepoint, deduplicating.
    final outputData = <Data>[];
    String? lastValue;

    for (final point in pData) {
      final parentLV = parseHexToLV(point.value, parentWidth);
      final sliced = parentLV.getRange(lo, hi + 1);
      final formatted = _fmtLV(sliced);

      if (formatted != lastValue) {
        outputData.add(Data(time: point.time, value: formatted));
        lastValue = formatted;
      }
    }

    debugPrint(
      '[BitSlice] "$signalId": '
      'bits [$hi:$lo] of "$parentPath" ($parentWidth bits) → '
      '${outputData.length} transitions (${fieldWidth}b)',
    );

    return WaveformData(signalId: signalId, data: outputData, isComputed: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // On-demand module expansion
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> expandAllSlimModules() async {
    if (_schematicModules == null || fetchModuleSchematic == null) {
      return;
    }
    final modules = _schematicModules!;
    var anyExpanded = false;
    for (final entry in modules.entries.toList()) {
      final defName = entry.key;
      if (_expandedModules.contains(defName)) {
        continue;
      }
      final modData = entry.value as Map<String, dynamic>;
      if (!isSlimModule(modData)) {
        continue;
      }
      final fullData = await _fetchModuleOnce(defName);
      if (fullData != null) {
        for (final e in fullData.entries) {
          modules[e.key] = e.value;
        }
        _expandedModules.add(defName);
        anyExpanded = true;
      }
    }
    if (anyExpanded) {
      _evaluator = null;
      sharedEvaluator = null;
      evalCache?.reset();
      debugPrint(
        '[BaseApi] expandAllSlimModules: '
        'expanded ${_expandedModules.length} modules, cache reset',
      );
    }
  }

  /// Ensure modules along [signalId]'s path have full connectivity.
  Future<bool> ensureFullModules(String signalId) async {
    if (_schematicModules == null || fetchModuleSchematic == null) {
      return false;
    }

    final modules = _schematicModules!;
    final parts = signalId.split('/');
    if (parts.length < 2) {
      return false;
    }

    String? topKey;
    for (final e in modules.entries) {
      final attrs = (e.value as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (attrs?['top'] == 1) {
        topKey = e.key;
        break;
      }
    }
    topKey ??= modules.keys.isNotEmpty ? modules.keys.first : null;
    if (topKey == null) {
      return false;
    }

    var expanded = false;
    var defName = topKey;

    for (var i = 1; i < parts.length - 1; i++) {
      final cellName = parts[i];
      final modData = modules[defName] as Map<String, dynamic>?;
      if (modData == null) {
        break;
      }

      if (!_expandedModules.contains(defName) && isSlimModule(modData)) {
        final fullData = await _fetchModuleOnce(defName);
        if (fullData != null) {
          for (final entry in fullData.entries) {
            modules[entry.key] = entry.value;
          }
          _expandedModules.add(defName);
          expanded = true;
        }
      }

      final cells = (modules[defName] as Map<String, dynamic>?)?['cells']
              as Map<String, dynamic>? ??
          {};
      final cell = cells[cellName] as Map<String, dynamic>?;
      final nextType = cell?['type'] as String?;
      if (nextType == null || !modules.containsKey(nextType)) {
        break;
      }
      defName = nextType;
    }

    // Also expand the leaf module.
    final leafMod = modules[defName] as Map<String, dynamic>?;
    if (leafMod != null &&
        !_expandedModules.contains(defName) &&
        isSlimModule(leafMod)) {
      final fullData = await _fetchModuleOnce(defName);
      if (fullData != null) {
        for (final entry in fullData.entries) {
          modules[entry.key] = entry.value;
        }
        _expandedModules.add(defName);
        expanded = true;
      }
    }

    return expanded;
  }

  /// Fetch a module's full data, coalescing concurrent requests.
  Future<Map<String, dynamic>?> _fetchModuleOnce(String defName) =>
      _inFlightExpansions.putIfAbsent(defName, () async {
        debugPrint('[BaseApi] Expanding slim module: $defName');
        try {
          return await fetchModuleSchematic!(defName);
        } finally {
          final _ = _inFlightExpansions.remove(defName);
        }
      });

  /// Whether a module is slim (cells exist but lack `connections`).
  static bool isSlimModule(Map<String, dynamic> moduleData) {
    final cells = moduleData['cells'] as Map<String, dynamic>? ?? {};
    for (final cellEntry in cells.values) {
      final cell = cellEntry as Map<String, dynamic>;
      if (cell.containsKey('connections')) {
        return false;
      }
    }
    return cells.isNotEmpty;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Evaluator & helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Get or create the client-side [NetlistEvaluator].
  NetlistEvaluator? _getEvaluator() =>
      sharedEvaluator ??
      (_evaluator ??= _schematicModules != null
          ? NetlistEvaluator(_schematicModules!, evalCache)
          : null);

  /// Resolve a signal pathname to a [SignalOccurrence].
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

  /// Format a [LogicValue] as a string.
  /// Format a [LogicValue] using the same compact representation as the
  /// server-side `WaveformService._formatLogicValue`:
  ///   - 1-bit: no width prefix ("0", "1", "x", "z")
  ///   - multi-bit valid: "0xHEX"
  ///   - multi-bit invalid (x/z): raw string without width prefix
  static String _fmtLV(LogicValue lv) {
    if (lv.width == 0) {
      return '';
    }
    return lv.toString();
  }

  /// Clear all cached data.
  void clearCache() {
    _cachedStructure = null;
    _waveformCache.clear();
    _hierarchyService = null;
    _evaluator = null;
    _expandedModules.clear();
    evalCache?.reset();
  }
}
