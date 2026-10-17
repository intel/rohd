// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_process_waveform_data_source.dart
// Waveform data source that calls WaveformDataService directly (in-process).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart' show WaveformDataService;
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_data_source.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// [WaveformDataSource] that calls [WaveformDataService] directly in the same
/// process.
///
/// Mirrors the VM-service-backed waveform data source but bypasses the VM
/// service WebSocket protocol entirely.  JSON serialization/deserialization is
/// still used because [WaveformDataService]'s public API returns JSON strings
/// (the same format as the `ext.rohd.*` service extensions).
///
/// This is the waveform-side counterpart of the in-process tree data source.
class InProcessWaveformDataSource implements WaveformDataSource {
  /// Human-readable name for this data source.
  final String name;

  bool _connected = true;

  /// Monotonic ID for compact waveform debug logs.
  int _compactRequestSequence = 0;

  int _lastFetchedTime = 0;

  /// Stream controller for update events.
  final _updateController = StreamController<WaveformUpdateEvent>.broadcast();

  /// Creates an in-process waveform data source.
  InProcessWaveformDataSource({this.name = 'In-Process'});

  @override
  bool get isConnected => _connected;

  @override
  String get modeDescription => 'In-Process ($name)';

  @override
  int get lastFetchedTime => _lastFetchedTime;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updateController.stream;

  // ─────────────────────────────────────────────────────────────────────────
  // Current time
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<int?> getCurrentTime() async {
    if (!_connected) {
      return null;
    }
    try {
      return WaveformDataService.instance.currentTime;
    } on Exception catch (e) {
      debugPrint('[InProcessWaveform] getCurrentTime error: $e');
      return null;
    }
  }

  /// Fetch current time and emit an update event (mirrors
  /// VmServiceWaveformDataSource.fetchAndEmitCurrentTime).
  Future<void> fetchAndEmitCurrentTime() async {
    final time = await getCurrentTime();
    if (time != null && time > _lastFetchedTime) {
      _lastFetchedTime = time;
      _updateController.add(
        WaveformUpdateEvent(
          incrementalData: const [],
          reason: WaveformUpdateReason.periodic,
          upToTime: time,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snapshots
  // ─────────────────────────────────────────────────────────────────────────

  @override
  // Not used — compact snapshot is preferred.
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getSnapshotCompact(int time) async {
    if (!_connected) {
      return null;
    }
    try {
      final jsonStr = WaveformDataService.instance.getSnapshotCompactJSON(time);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } on Exception catch (e) {
      debugPrint('[InProcessWaveform] getSnapshotCompact error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform data (legacy string-keyed)
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) {
    // Delegate to the timepoint-based path which calls WaveformDataService.
    final timepoints = <String, int>{
      for (final id in signalIds) id: startTime ?? 0,
    };
    return getWaveformDataWithTimepoints(signalTimepoints: timepoints);
  }

  @override
  Future<List<WaveformData>> getWaveformDataSince({
    required List<String> signalIds,
    required int sinceTime,
  }) {
    // Build per-signal timepoints and delegate.
    final timepoints = <String, int>{for (final id in signalIds) id: sinceTime};
    return getWaveformDataWithTimepoints(signalTimepoints: timepoints);
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepoints({
    required Map<String, int> signalTimepoints,
  }) async {
    if (!_connected) {
      return const [];
    }
    try {
      final jsonStr = WaveformDataService.instance.getDataWithTimepointsJSON(
        jsonEncode(signalTimepoints),
      );
      final list = jsonDecode(jsonStr) as List;
      return list.map((e) {
        final map = e as Map<String, dynamic>;
        return WaveformData.fromJson(map);
      }).toList();
    } on Exception catch (e) {
      debugPrint('[InProcessWaveform] getWaveformDataWithTimepoints error: $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform data (compact address-keyed)
  // ─────────────────────────────────────────────────────────────────────────

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
        '[InProcessWaveform][$requestId] compact request skipped: '
        'disconnected',
      );
      return const [];
    }
    try {
      debugPrint(
        '[InProcessWaveform][$requestId] compact request: '
        '${signalAddresses.length} addresses, '
        'range=${startTime ?? 0}..${endTime ?? -1}, '
        'sample=${signalAddresses.take(5).join(", ")}',
      );
      final jsonStr = WaveformDataService.instance.getWaveformsCompactJSON(
        jsonEncode(signalAddresses),
        startTime ?? 0,
        endTime ?? -1,
      );
      final list = jsonDecode(jsonStr) as List;
      final parsed = _parseCompactWaveformData(list, addressToSignalId);
      final pointCount = parsed.fold<int>(
        0,
        (total, waveform) => total + waveform.data.length,
      );
      debugPrint(
        '[InProcessWaveform][$requestId] compact parsed: '
        '${parsed.length} waveforms / $pointCount points',
      );
      return parsed;
    } on Exception catch (e) {
      debugPrint('[InProcessWaveform] getWaveformDataCompact error: $e');
      return const [];
    }
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async {
    final requestId = ++_compactRequestSequence;
    if (!_connected) {
      debugPrint(
        '[InProcessWaveform][$requestId] compact timepoint request skipped: '
        'disconnected',
      );
      return const [];
    }
    try {
      debugPrint(
        '[InProcessWaveform][$requestId] compact timepoint request: '
        '${signalTimepoints.length} addresses, '
        'sample=${signalTimepoints.keys.take(5).join(", ")}',
      );
      final jsonStr = WaveformDataService.instance
          .getDataWithTimepointsCompactJSON(jsonEncode(signalTimepoints));
      final list = jsonDecode(jsonStr) as List;
      final parsed = _parseCompactWaveformData(list, addressToSignalId);
      final pointCount = parsed.fold<int>(
        0,
        (total, waveform) => total + waveform.data.length,
      );
      debugPrint(
        '[InProcessWaveform][$requestId] compact timepoint parsed: '
        '${parsed.length} waveforms / $pointCount points',
      );
      return parsed;
    } on Exception catch (e) {
      debugPrint(
        '[InProcessWaveform] getWaveformDataWithTimepointsCompact '
        'error: $e',
      );
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Signal dictionary
  // ─────────────────────────────────────────────────────────────────────────

  // Dictionary is derived locally from ModuleStructure —
  // same as VmServiceWaveformDataSource.
  @override
  Future<List<Map<String, dynamic>>?> getSignalDictionary() async => null;

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse compact waveform JSON: `[{"i": addr, "d": [{"t":, "v":}]}]`.
  List<WaveformData> _parseCompactWaveformData(
    List<dynamic> list,
    Map<String, String> addressToSignalId,
  ) {
    final result = <WaveformData>[];
    var unmappedCount = 0;
    for (final entry in list) {
      final map = entry as Map<String, dynamic>;
      final addr = map['i'] as String;
      final signalId = addressToSignalId[addr];
      if (signalId == null) {
        unmappedCount++;
        continue;
      }
      final dataList = map['d'] as List? ?? [];
      final data = dataList.map((d) {
        final dm = d as Map<String, dynamic>;
        return Data(time: dm['t'] as int, value: dm['v'].toString());
      }).toList();
      result.add(WaveformData(signalId: signalId, data: data));
    }
    if (unmappedCount > 0) {
      debugPrint(
        '[InProcessWaveform] compact parse skipped $unmappedCount unmapped '
        'addresses from ${list.length} rows',
      );
    }
    return result;
  }

  /// Clear cached data and reset last fetched time.
  void clearCache() {
    _lastFetchedTime = 0;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    await _updateController.close();
  }
}
