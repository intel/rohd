// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// integer_math.dart
// Exact integer logarithm and power-of-two helpers.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.kirkpatrick@intel.com>

/// Exact base-two math helpers for [int] values.
extension IntegerMath on int {
  /// Returns the floor of the base-two logarithm.
  ///
  /// Returns zero for zero. Negative values are not supported.
  int get log2Floor {
    if (this < 0) {
      throw ArgumentError.value(this, 'this', 'must be non-negative.');
    }
    return this == 0 ? 0 : bitLength - 1;
  }

  /// Returns the ceiling of the base-two logarithm.
  ///
  /// Returns zero for zero and one. Negative values are not supported.
  int get log2Ceil {
    if (this < 0) {
      throw ArgumentError.value(this, 'this', 'must be non-negative.');
    }
    return this <= 1 ? 0 : (this - 1).bitLength;
  }

  /// Whether this value is a positive power of two.
  bool get isPowerOfTwo => this > 0 && (this & (this - 1)) == 0;
}

/// Exact base-two math helpers for [BigInt] values.
extension BigIntMath on BigInt {
  /// Returns the floor of the base-two logarithm.
  ///
  /// Returns zero for zero. Negative values are not supported.
  int get log2Floor {
    if (isNegative) {
      throw ArgumentError.value(this, 'this', 'must be non-negative.');
    }
    return this == BigInt.zero ? 0 : bitLength - 1;
  }

  /// Returns the ceiling of the base-two logarithm.
  ///
  /// Returns zero for zero and one. Negative values are not supported.
  int get log2Ceil {
    if (isNegative) {
      throw ArgumentError.value(this, 'this', 'must be non-negative.');
    }
    return this <= BigInt.one ? 0 : (this - BigInt.one).bitLength;
  }

  /// Whether this value is a positive power of two.
  bool get isPowerOfTwo =>
      this > BigInt.zero && (this & (this - BigInt.one)) == BigInt.zero;
}
