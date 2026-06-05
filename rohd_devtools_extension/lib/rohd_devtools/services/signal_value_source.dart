// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_source.dart
// Shared extension-side abstraction for fetching live signal values.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Raw snapshot payload keyed by signal ID or full signal path.
typedef SignalSnapshotData = Map<String, Map<String, dynamic>>;

/// Minimal update event used by the shared snapshot overlay flow.
class SignalValueUpdateEvent {
  /// Simulation time covered by the update, in picoseconds.
  final int upToTime;

  /// Whether the update indicates value data is available.
  final bool hasData;

  /// Human-readable update reason for diagnostics.
  final String reason;

  /// Creates a [SignalValueUpdateEvent].
  const SignalValueUpdateEvent({
    required this.upToTime,
    required this.hasData,
    required this.reason,
  });
}

/// Shared abstraction for value-only snapshot fetches and update ticks.
abstract interface class SignalValueSource {
  /// Stream of live update ticks, if this source supports them.
  Stream<SignalValueUpdateEvent>? get updates;

  /// Returns the current simulation time, if available.
  Future<int?> getCurrentTime();

  /// Fetch a value snapshot at [timePs].
  Future<SignalSnapshotData?> getSnapshot(int timePs);
}
