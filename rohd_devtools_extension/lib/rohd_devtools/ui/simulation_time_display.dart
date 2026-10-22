// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// simulation_time_display.dart
// Display-level formatter for simulation time values.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Display settings for simulation time values.
class SimulationTimeDisplay {
  /// Default display settings when no unit is known.
  static const none = SimulationTimeDisplay();

  /// Optional unit suffix used when formatting simulation time.
  final String? unit;

  /// Creates display settings for simulation time values.
  const SimulationTimeDisplay({this.unit});

  /// Formats [time] with the configured unit, if any.
  String format(int time) {
    final trimmedUnit = unit?.trim();
    if (trimmedUnit == null || trimmedUnit.isEmpty) {
      return time.toString();
    }

    return '$time$trimmedUnit';
  }
}
