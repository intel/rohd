// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_process_transport.dart
// In-process transport — calls WaveformDataService/ModuleServices directly.
//
// This is the loopback counterpart of VmServiceTransport: instead of
// sending RPCs over a WebSocket, it calls the ROHD diagnostics singletons
// directly in the same isolate.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart'
    show ModuleServices, NetlistService, WaveformDataService;
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// [RohdServiceTransport] that calls [WaveformDataService] and [ModuleServices]
/// directly in the same process.
///
/// No WebSocket, no JSON-over-wire — the cheapest possible transport.
/// JSON serialization/deserialization is still needed because the server
/// singletons' public API returns JSON strings.
class InProcessTransport implements RohdServiceTransport {
  /// Human-readable name for logging.
  final String name;

  bool _connected = true;
  int _lastFetchedTime = 0;

  /// Stream controller for update events.
  final _updateController = StreamController<WaveformUpdateEvent>.broadcast();

  /// Creates an in-process transport.
  InProcessTransport({this.name = 'In-Process'});

  @override
  bool get isConnected => _connected;

  @override
  String get modeDescription => 'In-Process ($name)';

  @override
  int get lastFetchedTime => _lastFetchedTime;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updateController.stream;

  /// Fetch current time and emit an update event.
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
  // Waveform RPCs
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<int?> getCurrentTime() async {
    if (!_connected) {
      return null;
    }
    try {
      return WaveformDataService.instance.currentTime;
    } on Exception catch (e) {
      debugPrint('[InProcessTransport] getCurrentTime error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getSnapshotCompact(int time) async {
    if (!_connected) {
      return null;
    }
    try {
      final jsonStr = WaveformDataService.instance.getSnapshotCompactJSON(time);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } on Exception catch (e) {
      debugPrint('[InProcessTransport] getSnapshotCompact error: $e');
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
      return const [];
    }
    try {
      final jsonStr = WaveformDataService.instance.getWaveformsCompactJSON(
        jsonEncode(signalAddresses),
        startTime ?? 0,
        endTime ?? -1,
      );
      final list = jsonDecode(jsonStr) as List;
      return _parseCompactWaveformData(list, addressToSignalId);
    } on Exception catch (e) {
      debugPrint('[InProcessTransport] getWaveformDataCompact error: $e');
      return const [];
    }
  }

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async {
    if (!_connected) {
      return const [];
    }
    try {
      final jsonStr = WaveformDataService.instance
          .getDataWithTimepointsCompactJSON(jsonEncode(signalTimepoints));
      final list = jsonDecode(jsonStr) as List;
      return _parseCompactWaveformData(list, addressToSignalId);
    } on Exception catch (e) {
      debugPrint(
        '[InProcessTransport] '
        'getWaveformDataWithTimepointsCompact error: $e',
      );
      return const [];
    }
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
      final jsonString = NetlistService.current?.slimJson ??
          ModuleServices.instance.hierarchyJson;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } on Exception catch (e) {
      debugPrint('[InProcessTransport] getModuleTree error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getModuleNetlist(String definitionName) async {
    if (!_connected) {
      return null;
    }
    try {
      final jsonString = NetlistService.current?.moduleJson(definitionName);
      if (jsonString == null) {
        return null;
      }
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      if (decoded.containsKey('status')) {
        return null;
      }
      // New format wraps module data under a 'modules' key.
      if (decoded.containsKey('modules') &&
          !decoded.containsKey(definitionName)) {
        return decoded['modules'] as Map<String, dynamic>;
      }
      return decoded;
    } on Exception catch (e) {
      debugPrint('[InProcessTransport] getModuleNetlist error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _connected = false;
    await _updateController.close();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parsing helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse compact (address-keyed) waveform JSON into [WaveformData] list.
  ///
  /// The compact format uses abbreviated keys: `i` (address), `d` (data
  /// array), `t` (time), `v` (value).
  List<WaveformData> _parseCompactWaveformData(
    List<dynamic> list,
    Map<String, String> addressToSignalId,
  ) {
    final result = <WaveformData>[];
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final addr = map['i'] as String;
      final signalId = addressToSignalId[addr];
      if (signalId == null) {
        continue;
      }
      final rawData = map['d'] as List<dynamic>? ?? const [];
      final dataPoints = rawData.map((d) {
        final dp = d as Map<String, dynamic>;
        return Data(time: dp['t'] as int, value: dp['v'].toString());
      }).toList();
      result.add(WaveformData(signalId: signalId, data: dataPoints));
    }
    return result;
  }
}
