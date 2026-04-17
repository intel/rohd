// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_modules.dart
// Web-safe module class definition for the Tree of Two-Input Modules example.
//
// Extracted from example/tree.dart so it can be imported in web-targeted code.
//
// Original author: Max Korbel

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

// ──────────────────────────────────────────────────────────────────
// TreeOfTwoInputModules
// ──────────────────────────────────────────────────────────────────

/// A logarithmic-height tree of arbitrary two-input/one-output modules.
///
/// Recursively instantiates itself, splitting the input list in half at each
/// level.  The operation [op] is applied to combine pairs of results.
class TreeOfTwoInputModules extends Module {
  /// The combining operation (internal use only).
  @protected
  final Logic Function(Logic a, Logic b) op;

  final List<Logic> _seq = [];

  /// The combined output of the tree.
  Logic get out => output('out');

  /// Creates a tree that reduces [seq] using [op].
  ///
  /// Recursively splits [seq] in half until single elements remain,
  /// then combines them pair-wise with the supplied operation.
  TreeOfTwoInputModules(List<Logic> seq, this.op)
      : super(
          name: 'tree_of_two_input_modules',
          definitionName: 'TreeMax_N${seq.length}',
        ) {
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
      final a =
          TreeOfTwoInputModules(_seq.getRange(0, _seq.length ~/ 2).toList(), op)
              .out;
      final b = TreeOfTwoInputModules(
              _seq.getRange(_seq.length ~/ 2, _seq.length).toList(), op)
          .out;
      out <= op(a, b);
    }
  }
}
