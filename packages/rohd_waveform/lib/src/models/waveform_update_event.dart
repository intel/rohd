// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_update_event.dart
// Event model for incremental waveform updates from live simulations.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/src/models/waveform_data.dart';

/// Reasons for a waveform update event.
enum WaveformUpdateReason {
  /// Update triggered by hitting a breakpoint.
  breakpoint,

  /// Manual refresh requested by user.
  manual,

  /// Periodic update during continuous simulation.
  periodic,

  /// Final update when simulation completes.
  simulationComplete,

  /// Initial data load.
  initial,

  /// Waveform structure (signal dictionary) has become available.
  ///
  /// Emitted when a debug-pause probe discovers the ROHD WaveformService
  /// for the first time.  Listeners should re-fetch the module structure
  /// so the signal tree appears in the UI.
  structureAvailable,
}

/// A waveform update event containing incremental data.
///
/// Used to communicate incremental waveform data from live simulations
/// to the waveform viewer UI.
class WaveformUpdateEvent {
  /// The new waveform data since the last update.
  final List<WaveformData> incrementalData;

  /// Reason for this update.
  final WaveformUpdateReason reason;

  /// The simulation time up to which data is included.
  final int upToTime;

  /// Creates a waveform update event.
  WaveformUpdateEvent({
    required this.incrementalData,
    required this.reason,
    required this.upToTime,
  });

  /// Whether this update contains any new data.
  bool get hasData => incrementalData.isNotEmpty;
}
