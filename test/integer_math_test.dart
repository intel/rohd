// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// integer_math_test.dart
// Tests exact integer math helpers.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  group('int integer math', () {
    test('computes exact base-two logarithms', () {
      expect(0.log2Floor, 0);
      expect(0.log2Ceil, 0);
      expect(1.log2Floor, 0);
      expect(1.log2Ceil, 0);
      expect(2.log2Floor, 1);
      expect(2.log2Ceil, 1);
      expect(3.log2Floor, 1);
      expect(3.log2Ceil, 2);
      expect(8.log2Floor, 3);
      expect(8.log2Ceil, 3);
      expect(9.log2Floor, 3);
      expect(9.log2Ceil, 4);
    });

    test('identifies powers of two', () {
      expect(0.isPowerOfTwo, isFalse);
      expect(1.isPowerOfTwo, isTrue);
      expect(2.isPowerOfTwo, isTrue);
      expect(3.isPowerOfTwo, isFalse);
      expect((1 << 30).isPowerOfTwo, isTrue);
    });

    test('rejects negative values', () {
      expect(() => (-1).log2Floor, throwsArgumentError);
      expect(() => (-1).log2Ceil, throwsArgumentError);
    });
  });

  group('BigInt integer math', () {
    test('computes exact base-two logarithms', () {
      final power = BigInt.one << 200;

      expect(BigInt.zero.log2Floor, 0);
      expect(BigInt.zero.log2Ceil, 0);
      expect(power.log2Floor, 200);
      expect(power.log2Ceil, 200);
      expect((power + BigInt.one).log2Floor, 200);
      expect((power + BigInt.one).log2Ceil, 201);
    });

    test('identifies powers of two', () {
      final power = BigInt.one << 200;

      expect(BigInt.zero.isPowerOfTwo, isFalse);
      expect(power.isPowerOfTwo, isTrue);
      expect((power + BigInt.one).isPowerOfTwo, isFalse);
    });

    test('rejects negative values', () {
      expect(() => (-BigInt.one).log2Floor, throwsArgumentError);
      expect(() => (-BigInt.one).log2Ceil, throwsArgumentError);
    });
  });
}
