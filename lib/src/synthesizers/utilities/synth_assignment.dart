// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_assignment.dart
// Definition for assignments
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents an assignment between two signals.
class SynthAssignment {
  /// The initial destination.
  SynthLogic _dst;

  /// The destination being driven by this assignment.
  ///
  /// Ensures it's always using the most up-to-date version.
  SynthLogic get dst {
    if (_dst.replacement != null) {
      _dst = _dst.replacement!;
      assert(_dst.replacement == null, 'should not be a chain...');
    }
    return _dst;
  }

  /// The initial source.
  SynthLogic _src;

  /// The source driving in this assignment.
  ///
  /// Ensures it's always using the most up-to-date version.
  SynthLogic get src {
    if (_src.replacement != null) {
      _src = _src.replacement!;
      assert(_src.replacement == null, 'should not be a chain...');
    }
    return _src;
  }

  /// Constructs a representation of an assignment.
  SynthAssignment(this._src, this._dst);

  @override
  String toString() => '$dst <= $src';
}

class PartialSynthAssignment extends SynthAssignment {
  int upperIndex;
  int lowerIndex;

  /// Constructs a representation of a partial assignment.
  PartialSynthAssignment(SynthLogic src, SynthLogic dst,
      {required this.upperIndex, required this.lowerIndex})
      : super(src, dst);

  @override
  String toString() => '$dst[$upperIndex:$lowerIndex] <= $src';
}
