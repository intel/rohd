// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// coeff_bank.dart
// Coefficient storage module for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// A coefficient storage module backed by a [LogicArray] input port.
///
/// Accepts a [LogicArray] of per-tap coefficients via [addInputArray]
/// and a tap index, then mux-selects the corresponding coefficient.
class CoeffBank extends Module {
  /// The coefficient value at the selected index.
  Logic get coeffOut => output('coeffOut');

  /// The per-tap coefficient array (registered input port).
  @protected
  LogicArray get coeffArray => input('coeffArray') as LogicArray;

  /// The tap index input.
  @protected
  Logic get tapIndex => input('tapIndex');

  /// Number of taps.
  final int numTaps;

  /// Data width.
  final int dataWidth;

  /// Creates a [CoeffBank] with [numTaps] taps at [dataWidth] bits.
  ///
  /// [coefficients] is a [LogicArray] with one element per tap —
  /// registered as an input port via [addInputArray].
  /// [tapIndex] selects the active coefficient.
  CoeffBank(Logic tapIndex, LogicArray coefficients,
      {required this.numTaps,
      required this.dataWidth,
      super.name = 'CoeffBank'})
      : super(definitionName: 'CoeffBank_T${numTaps}_W$dataWidth') {
    // Register ports
    tapIndex = addInput('tapIndex', tapIndex, width: tapIndex.width);
    final coeffArray = addInputArray('coeffArray', coefficients,
        dimensions: [numTaps], elementWidth: dataWidth);
    final coeffOut = addOutput('coeffOut', width: dataWidth);

    // Mux-chain ROM: priority-select coefficient by tap index.
    Logic selected = Const(0, width: dataWidth);
    for (var i = numTaps - 1; i >= 0; i--) {
      selected = mux(
        tapIndex.eq(Const(i, width: tapIndex.width)).named('tapMatch$i'),
        coeffArray.elements[i],
        selected,
      );
    }
    coeffOut <= selected;
  }
}
