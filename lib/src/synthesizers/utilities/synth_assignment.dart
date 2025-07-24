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

  /// Used for assertions, checks if the widths meet proper expectations.
  bool _checkWidths() => _src.width == _dst.width;

  /// Constructs a representation of an assignment.
  SynthAssignment(this._src, this._dst) {
    assert(_checkWidths(), 'Signal width mismatch');
  }

  @override
  String toString() => '$dst <= $src';
}

/// Represents an assignment from a full source to a partial destination.
class PartialSynthAssignment extends SynthAssignment {
  /// The upper index of the destination.
  int dstUpperIndex;

  /// The lower index of the destination.
  int dstLowerIndex;

  @override
  bool _checkWidths() => _src.width == (dstUpperIndex - dstLowerIndex + 1);

  /// Constructs a representation of a partial assignment.
  PartialSynthAssignment(super._src, super._dst,
      {required this.dstUpperIndex, required this.dstLowerIndex})
      : assert(dstLowerIndex >= 0, 'Invalid lower index'),
        assert(dstUpperIndex < _dst.width, 'Invalid upper index');

  @override
  String toString() => '$dst[$dstUpperIndex:$dstLowerIndex] <= $src';
}
