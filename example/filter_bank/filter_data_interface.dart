// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_data_interface.dart
// Interface definition for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Tags for grouping port directions in [FilterDataInterface].
enum FilterPortTag {
  /// Ports carrying data into the filter (`sampleIn`, `validIn`).
  inputPorts,

  /// Ports carrying data out of the filter (`dataOut`, `validOut`).
  outputPorts,
}

/// An interface carrying sample data and control into/out of filter modules.
///
/// Groups ports by [FilterPortTag] so that [connectIO] can wire
/// inputs and outputs in a single call.
class FilterDataInterface extends Interface<FilterPortTag> {
  /// Input sample data bus.
  Logic get sampleIn => port('sampleIn');

  /// Input valid strobe.
  Logic get validIn => port('validIn');

  /// Output filtered data bus.
  Logic get dataOut => port('dataOut');

  /// Output valid strobe.
  Logic get validOut => port('validOut');

  /// The data width used by this interface.
  final int _dataWidth;

  /// Creates a [FilterDataInterface] with the given [dataWidth]
  /// (default 16 bits).
  FilterDataInterface({int dataWidth = 16}) : _dataWidth = dataWidth {
    setPorts([
      Logic.port('sampleIn', dataWidth),
      Logic.port('validIn'),
    ], [
      FilterPortTag.inputPorts
    ]);

    setPorts([
      Logic.port('dataOut', dataWidth),
      Logic.port('validOut'),
    ], [
      FilterPortTag.outputPorts
    ]);
  }

  @override

  /// Returns a new interface with the same data width.
  FilterDataInterface clone() => FilterDataInterface(dataWidth: _dataWidth);
}
