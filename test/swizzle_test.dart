/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// swizzle_test.dart
/// Tests for swizzling values
///
/// 2022 January 6
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  group('LogicValue', () {
    test('simple swizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .swizzle(),
          equals(LogicValues.ofString('10xz')));
    });
    test('simple rswizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .rswizzle(),
          equals(LogicValues.ofString('zx01')));
    });
  });
  group('LogicValues', () {
    test('simple swizzle', () {
      expect([LogicValues.ofString('10'), LogicValues.ofString('xz')].swizzle(),
          equals(LogicValues.ofString('10xz')));
    });

    test('simple rswizzle', () {
      expect(
          [LogicValues.ofString('10'), LogicValues.ofString('xz')].rswizzle(),
          equals(LogicValues.ofString('xz10')));
    });
  });
}
