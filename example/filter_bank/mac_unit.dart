// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mac_unit.dart
// Multiply-accumulate module for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// A pipelined multiply-accumulate unit.
///
/// Pipeline stage 0: multiply sample × coefficient
/// Pipeline stage 1: add product to running accumulator
class MacUnit extends Module {
  /// Accumulated result.
  Logic get result => output('result');

  /// Sample data input.
  @protected
  Logic get sampleInPin => input('sampleIn');

  /// Coefficient input.
  @protected
  Logic get coeffInPin => input('coeffIn');

  /// Accumulator input.
  @protected
  Logic get accumInPin => input('accumIn');

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Enable input.
  @protected
  Logic get enablePin => input('enable');

  /// Data width.
  final int dataWidth;

  /// Creates a [MacUnit] that multiplies [sampleIn] by [coeffIn] in
  /// stage 0 and adds the product to [accumIn] in stage 1.
  ///
  /// [clk], [reset], and [enable] control the pipeline registers.
  MacUnit(Logic sampleIn, Logic coeffIn, Logic accumIn, Logic clk, Logic reset,
      Logic enable,
      {required this.dataWidth, super.name = 'MacUnit'})
      : super(definitionName: 'MacUnit_W$dataWidth') {
    sampleIn = addInput('sampleIn', sampleIn, width: dataWidth);
    coeffIn = addInput('coeffIn', coeffIn, width: dataWidth);
    accumIn = addInput('accumIn', accumIn, width: dataWidth);
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);
    final result = addOutput('result', width: dataWidth);

    // A 2-stage pipeline: multiply, then accumulate
    final pipe = Pipeline(
      clk,
      reset: reset,
      stages: [
        // Stage 0: multiply
        (p) => [
              // Product = sample * coefficient (truncated to dataWidth)
              p.get(sampleIn) <
                  (p.get(sampleIn) * p.get(coeffIn)).named('product'),
            ],
        // Stage 1: accumulate
        (p) => [
              p.get(sampleIn) <
                  (p.get(sampleIn) + p.get(accumIn)).named('macSum'),
            ],
      ],
      signals: [sampleIn, coeffIn, accumIn],
    );

    result <= pipe.get(sampleIn);
  }
}
