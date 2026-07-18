// Copyright (C) 2021-2026 Intel Corporation
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

  /// The width of the assignment (of both the [src] and [dst]).
  int get width => dst.width;

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

/// Represents an assignment from a partial source to a partial destination.
class RangeSynthAssignment extends PartialSynthAssignment {
  /// The upper index of the source.
  int srcUpperIndex;

  /// The lower index of the source.
  int srcLowerIndex;

  /// The width of the source and destination ranges.
  @override
  int get width => dstUpperIndex - dstLowerIndex + 1;

  @override
  bool _checkWidths() => width == srcUpperIndex - srcLowerIndex + 1;

  /// Constructs a representation of a range-to-range assignment.
  RangeSynthAssignment(super._src, super._dst,
      {required this.srcUpperIndex,
      required this.srcLowerIndex,
      required super.dstUpperIndex,
      required super.dstLowerIndex})
      : assert(srcLowerIndex >= 0, 'Invalid source lower index'),
        assert(srcUpperIndex < _src.width, 'Invalid source upper index');

  @override
  String toString() => '$dst[$dstUpperIndex:$dstLowerIndex] <= '
      '$src[$srcUpperIndex:$srcLowerIndex]';
}
