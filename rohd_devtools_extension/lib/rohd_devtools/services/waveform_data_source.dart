// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_data_source.dart
// Abstract interface for waveform data sources.
// Enables switching between DTD/VM connection and loopback modes for waveforms.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';

// Re-export WaveformUpdateEvent and WaveformUpdateReason from rohd_waveform
export 'package:rohd_waveform/rohd_waveform.dart'
    show WaveformUpdateEvent, WaveformUpdateReason;

/// Abstract interface for obtaining waveform data.
///
/// This parallels `TreeDataSource` but for waveform data instead of hierarchy.
/// Implementations can connect to:
/// - A live ROHD simulation via VM Service (VmServiceWaveformDataSource)
/// - A live ROHD simulation in-process (InProcessWaveformDataSource)
/// - VCD/GHW files via Wellen (WellenBackedWaveformDataSource)
///
/// Module structure (hierarchy, ports, signals) is NOT provided by this
/// interface — it comes through the rohd_hierarchy / TreeDataSource path.
abstract class WaveformDataSource {
  /// Whether this data source is currently connected/ready.
  bool get isConnected;

  /// Human-readable description of the data source mode.
  String get modeDescription;

  /// The last simulation time for which we have complete data.
  int get lastFetchedTime;

  /// Get waveform data for specified signals.
  ///
  /// [signalIds] - List of signal IDs to fetch data for.
  /// [startTime] - Start of time range (inclusive).
  /// [endTime] - End of time range (inclusive).
  ///
  /// Returns a list of [WaveformData] objects, one per signal.
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  });

  /// Get incremental waveform data since the last fetch.
  ///
  /// [signalIds] - List of signal IDs to fetch data for.
  /// [sinceTime] - Fetch data from this time onwards.
  ///
  /// This is the primary method for incremental updates when simulation
  /// is running and hits breakpoints.
  Future<List<WaveformData>> getWaveformDataSince({
    required List<String> signalIds,
    required int sinceTime,
  });

  /// Get incremental waveform data using per-signal timepoints.
  ///
  /// [signalTimepoints] - Map of signal ID to last fetched timepoint.
  ///
  /// This enables selective signal transmission where each signal can have
  /// a different last-fetched timepoint. Useful for:
  /// - Lazy loading: only fetch signals being displayed in UI
  /// - Dynamic signal addition: new signals start from timepoint 0
  /// - Independent signal advancement: each signal progresses at its own pace
  ///
  /// Returns only data points AFTER each signal's last timepoint.
  Future<List<WaveformData>> getWaveformDataWithTimepoints({
    required Map<String, int> signalTimepoints,
  });

  /// Stream of live waveform updates (for event-driven sources).
  ///
  /// Returns null if this source doesn't support live updates
  /// (e.g., static file sources).
  ///
  /// For VM Service sources, this stream emits events when:
  /// - Debugger pauses at a breakpoint
  /// - Simulation completes
  /// - Manual refresh is requested
  Stream<WaveformUpdateEvent>? get liveUpdates;

  /// Get the current simulation endpoint time.
  ///
  /// For VM service sources, this polls the running ROHD app to get the
  /// current simulation time (from WaveformService.currentTime).
  /// For loopback sources, this returns the current simulated time.
  ///
  /// This can be polled periodically (every 100-200ms) to monitor
  /// simulation progress and update the waveform display end time
  /// dynamically without waiting for breakpoints.
  ///
  /// Returns the current endpoint time, or null if unavailable.
  Future<int?> getCurrentTime();

  /// Get a snapshot of all signal values at the given [time].
  ///
  /// Returns a map of signal ID to a map containing:
  /// - `value`: the signal value at that time (String)
  /// - `name`: signal display name
  /// - `width`: signal bit width
  /// - `direction`: signal direction (if port)
  ///
  /// Returns null if the snapshot could not be retrieved.
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time);

  // ─────────────────────────────────────────────────────────────────────────
  // SignalOccurrence Dictionary & Compact Transport
  //
  // Uses dot-separated OccurrenceAddress strings instead of full
  // signal-path strings in JSON payloads, reducing size significantly
  // while remaining stable across slim/full netlist transitions.
  //
  // The VmServiceSignalWaveformApi derives the address dictionary
  // locally from the HierarchyOccurrence tree provided via
  // setExternalStructure().  Both sides build the same tree from the
  // slim JSON, so the addresses agree.  The getSignalDictionary()
  // method below is retained for loopback/file-backed sources that
  // may not have a HierarchyOccurrence tree.
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch the signal dictionary from the ROHD side.
  ///
  /// Returns a list of entries, each containing:
  /// - `i`: integer index
  /// - `id`: full signal path (String)
  /// - `name`: display name
  /// - `width`: bit width
  /// - `direction`: input/output/internal
  ///
  /// The dictionary is static for the lifetime of a simulation and should
  /// be cached by the consumer. Returns null if unavailable.
  ///
  /// Note: the VM-service waveform API no longer calls this method — it
  /// derives the dictionary from the module structure instead.  This
  /// method remains for other data sources (loopback, file-backed).
  Future<List<Map<String, dynamic>>?> getSignalDictionary();

  /// Get a compact snapshot: address-keyed values only.
  ///
  /// Requires that the consumer has built its address dictionary so it
  /// can resolve address keys back to signal IDs.
  ///
  /// Returns a map: `{ 'time': int, 'v': { '0.2.4': 'val', ... } }`
  /// or null if unavailable.
  Future<Map<String, dynamic>?> getSnapshotCompact(int time);

  /// Get compact waveform data using address strings.
  ///
  /// [signalAddresses] — dot-separated OccurrenceAddress strings.
  /// [startTime], [endTime] — time range (endTime -1 = current).
  ///
  /// Returns a list of compact waveform entries:
  /// `[{ 'i': '0.2.4', 'd': [{'t': 100, 'v': '1'}, ...] }, ...]`
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  });

  /// Get compact incremental waveform data with per-signal timepoints.
  ///
  /// [signalTimepoints] — map of address string → last timepoint.
  /// [addressToSignalId] — reverse lookup from dictionary.
  ///
  /// Returns a list of [WaveformData] with signal IDs restored.
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  });

  /// Dispose any resources held by this data source.
  Future<void> dispose();
}
