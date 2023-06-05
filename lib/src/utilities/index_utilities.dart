// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// index_utilities.dart
// Code for modifying and validating indices.
//
// 2023 June 1
// Author: Max Korbel <max.korbel@intel.com>

/// A utility class for modifying and validating indices.
abstract class IndexUtilities {
  /// Computes a modified version of an index into an array that allows for
  /// negative values to wrap around from the end.
  ///
  /// Guaranteed to either return an index in `[0, width)` or else throw
  /// an exception.
  ///
  /// If [allowWidth], then the range is `[0, width]` instead.
  static int wrapIndex(int originalIndex, int width,
      {bool allowWidth = false}) {
    final modifiedIndex =
        (originalIndex < 0) ? width + originalIndex : originalIndex;

    // check that it meets indexing requirements
    if (modifiedIndex < 0 ||
        modifiedIndex > width ||
        (!allowWidth && modifiedIndex == width)) {
      // The suggestion in the deprecation for this constructor is not available
      // before 2.19, so keep it in here for now.  Eventually, switch to the
      // new one.
      // ignore: deprecated_member_use
      throw IndexError(
          originalIndex,
          width,
          'IndexOutOfRange',
          'Index out of range:'
              ' $modifiedIndex(=$originalIndex) for width $width.',
          width);
    }

    return modifiedIndex;
  }

  /// Validates that the range is legal.
  static void validateRange(int startIndex, int endIndex,
      {bool allowEqual = true}) {
    if (endIndex < startIndex || (!allowEqual && endIndex == startIndex)) {
      throw RangeError('End $endIndex cannot be less than start $startIndex.');
    }
  }
}
