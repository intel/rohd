/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// tree.dart
/// An example taking advantage of some of ROHD's generation capabilities.
///
/// 2021 September 17
/// Author: Max Korbel <max.korbel@intel.com>
///

// Though we usually avoid them, for this example,
// allow `print` messages (disable lint):
// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

/// The below example demonstrates some aspects of the power of ROHD where
/// writing equivalent design code in SystemVerilog can be challenging or
/// impossible. The example is a port from an example used by Chisel.
///
/// The ROHD module `TreeOfTwoInputModules` is a succinct representation a
/// logarithmic-height tree of arbitrary two-input/one-output modules.
///
/// Some interesting things to note:
/// - The constructor for `TreeOfTwoInputModules` accepts two arguments:
///     - `seq` is a Dart `List` of arbitrary length of input elements.
///       The module dynamically assigns the input and output widths of the
///       module to match the width of the input elements. Additionally, the
///       total number of inputs to the module is dynamically determined at
///       run time.
///     - `_op` is a Dart `Function` (in Dart, `Function`s are first-class and
///       can be stored in variables). It expects a function which takes two
///       `Logic` inputs and provides one `Logic` output.
/// - This module recursively instantiates itself, but with different numbers of
///   inputs each time. The same module implementation can have a variable
///   number of inputs and different logic without any explicit
///   parameterization.

class TreeOfTwoInputModules extends Module {
  final Logic Function(Logic a, Logic b) _op;
  final List<Logic> _seq = [];
  Logic get out => output('out');

  TreeOfTwoInputModules(List<Logic> seq, this._op)
      : super(name: 'tree_of_two_input_modules') {
    if (seq.isEmpty) {
      throw Exception("Don't use TreeOfTwoInputModules with an empty sequence");
    }

    for (var i = 0; i < seq.length; i++) {
      _seq.add(addInput('seq$i', seq[i], width: seq[i].width));
    }
    addOutput('out', width: seq[0].width);

    if (_seq.length == 1) {
      out <= _seq[0];
    } else {
      final a = TreeOfTwoInputModules(
              _seq.getRange(0, _seq.length ~/ 2).toList(), _op)
          .out;
      final b = TreeOfTwoInputModules(
              _seq.getRange(_seq.length ~/ 2, _seq.length).toList(), _op)
          .out;
      out <= _op(a, b);
    }
  }
}

Future<void> main({bool noPrint = false}) async {
  // You could instantiate this module with some code such as:
  final tree = TreeOfTwoInputModules(
      List<Logic>.generate(16, (index) => Logic(width: 8)),
      (a, b) => mux(a > b, a, b));

  /// This instantiation code generates a list of sixteen 8-bit logic signals.
  /// The operation to be performed (`_op`) is to create a `Mux` (in this case,
  /// the `mux` helper function is used to create) which returns
  /// `a` if `a` is greater than `b`, otherwise `b`. Therefore, this
  /// instantiation creates a logarithmic-height tree of modules which outputs
  /// the largest 8-bit value. Note that `Mux` also needs no parameters, as it
  /// can automatically determine the appropriate size of `out` based on the
  /// inputs.
  ///
  /// A SystemVerilog implementation of this requires numerous module
  /// definitions and substantially more code.

  // Below will generate an output of the ROHD-generated SystemVerilog:
  await tree.build();
  final generatedSystemVerilog = tree.generateSynth();
  if (!noPrint) {
    print(generatedSystemVerilog);
  }
}
