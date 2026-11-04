// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_transport.dart
// Abstract transport interface for ROHD service communication.
//
// Defines the 6 RPCs that form the boundary between client-side algorithm
// (snapshot expansion, evaluator, synthesis) and the transport mechanism
// (VM service WebSocket vs in-process direct calls).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';

/// Abstract transport interface for ROHD service communication.
///
/// Implementations handle the mechanics of invoking server-side methods
/// and returning decoded Dart objects.  The client-side algorithm
/// (`BaseSignalWaveformApi`) consumes this interface without knowing
/// whether the calls go over a WebSocket or happen in-process.
///
/// **Waveform RPCs** (from `WaveformService`):
///
/// | Method | Server-side | Returns |
/// |--------|------------|---------|
/// | [getCurrentTime] | `WaveformDataService.instance.currentTime` | `int?` |
/// | [getSnapshotCompact] | `getSnapshotCompactJSON(time)` | decoded `Map` |
// ignore: lines_longer_than_80_chars
/// | [getWaveformDataCompact] | `getWaveformsCompactJSON(...)` | `List<WaveformData>` |
// ignore: lines_longer_than_80_chars
/// | [getWaveformDataWithTimepointsCompact] | `getDataWithTimepointsCompactJSON(...)` | `List<WaveformData>` |
///
/// **Hierarchy RPCs** (from `NetlistService`):
///
/// | Method | Server-side | Returns |
/// |--------|------------|--------|
/// | [getModuleTree] | `NetlistService.current?.slimJson` | decoded `Map` |
// ignore: lines_longer_than_80_chars
/// | [getModuleNetlist] | `NetlistService.current?.moduleJson(name)` | decoded `Map?` |
abstract class RohdServiceTransport {
  /// Whether the transport is currently connected and operational.
  bool get isConnected;

  /// Human-readable description of the transport mode.
  String get modeDescription;

  /// The last simulation time for which we have complete data.
  int get lastFetchedTime;

  /// Stream of live waveform updates (breakpoint pauses, simulation
  /// completion, etc.).  Returns `null` if this transport doesn't
  /// support live update events.
  Stream<WaveformUpdateEvent>? get liveUpdates;

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform RPCs
  // ─────────────────────────────────────────────────────────────────────────

  /// Get the current simulation endpoint time.
  ///
  /// Returns `null` if the time cannot be determined.
  Future<int?> getCurrentTime();

  /// Get a compact (address-keyed) snapshot of all signal values at [time].
  ///
  /// Returns a decoded map:
  /// ```json
  /// { "time": int, "v": { "0.2.4": "val", ... } }
  /// ```
  /// or `null` if unavailable.
  Future<Map<String, dynamic>?> getSnapshotCompact(int time);

  /// Fetch waveform data for signals identified by compact addresses.
  ///
  /// [signalAddresses] — dot-separated `OccurrenceAddress` strings.
  /// [addressToSignalId] — maps each address back to its full signal ID.
  /// [startTime], [endTime] — optional time range.
  ///
  /// Returns decoded [WaveformData] objects with signal IDs restored.
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  });

  /// Fetch incremental waveform data using per-signal timepoints.
  ///
  /// [signalTimepoints] — map of address → last-fetched timepoint.
  /// [addressToSignalId] — maps each address back to its full signal ID.
  ///
  /// Returns only data points AFTER each signal's last timepoint.
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Hierarchy RPCs
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch the full module tree (hierarchy + slim schematic).
  ///
  /// Returns the decoded JSON from `NetlistService.current?.slimJson`
  /// (falling back to `ModuleServices.instance.hierarchyJson`),
  /// or `null` if unavailable.
  Future<Map<String, dynamic>?> getModuleTree();

  /// Fetch the full schematic data for a single module definition.
  ///
  /// Returns `{"DefinitionName": { ports, cells, netnames }}` or `null`.
  Future<Map<String, dynamic>?> getModuleNetlist(String definitionName);

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Release resources held by this transport.
  Future<void> dispose();
}
