/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus_test.dart
/// Unit tests for bus-related operations
///
/// 2022 May 4
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  group('extend', () {
    test('extend with same width returns same thing', () {
      var original = LogicValue.ofString('0101xz0101');
      var modified = original.extend(original.width, LogicValue.x);
      expect(modified, equals(original));
    });
    test('extend with less width throws exception', () {
      var original = LogicValue.ofString('0101xz0101');
      expect(() => original.extend(original.width - 2, LogicValue.x),
          throwsException);
    });
    test('extend with more width properly extends', () {
      var original = LogicValue.ofString('0101xz0101');
      var modified = original.extend(original.width + 3, LogicValue.x);
      expect(modified, equals(LogicValue.ofString('xxx0101xz0101')));
    });
    test('zero extend pads 0s', () {
      var original = LogicValue.ofString('0101xz0101');
      var modified = original.zeroExtend(original.width + 3);
      expect(modified, equals(LogicValue.ofString('0000101xz0101')));
    });
    test('sign extend for positive number pads 0s', () {
      var original = LogicValue.ofString('0101xz0101');
      var modified = original.signExtend(original.width + 3);
      expect(modified, equals(LogicValue.ofString('0000101xz0101')));
    });
    test('sign extend for negative number pads 1s', () {
      var original = LogicValue.ofString('1101xz0101');
      var modified = original.signExtend(original.width + 3);
      expect(modified, equals(LogicValue.ofString('1111101xz0101')));
    });
  });

  group('withSet', () {
    test('setting with bigger number throws exception', () {
      var original = LogicValue.ofString('1101xz0101');
      expect(() => original.withSet(0, LogicValue.ofString('00001101xz0101')),
          throwsException);
    });
    test('setting with number in middle overrun throws exception', () {
      var original = LogicValue.ofString('1101xz0101');
      expect(() => original.withSet(7, LogicValue.ofString('1111')),
          throwsException);
    });
    test('setting same width returns only new', () {
      var original = LogicValue.ofString('1101xz0101');
      var newVal = LogicValue.ofString('1111001111');
      var modified = original.withSet(0, newVal);
      expect(modified, equals(newVal));
    });
    test('setting at front', () {
      var original = LogicValue.ofString('1101xz0101');
      var newVal = LogicValue.ofString('1111');
      var modified = original.withSet(0, newVal);
      expect(modified, equals(LogicValue.ofString('1101xz1111')));
    });
    test('setting at end', () {
      var original = LogicValue.ofString('xxxxxz0101');
      var newVal = LogicValue.ofString('1111');
      var modified = original.withSet(6, newVal);
      expect(modified, equals(LogicValue.ofString('1111xz0101')));
    });
    test('setting in the middle', () {
      var original = LogicValue.ofString('xxxxxxxxxx');
      var newVal = LogicValue.ofString('1111');
      var modified = original.withSet(3, newVal);
      expect(modified, equals(LogicValue.ofString('xxx1111xxx')));
    });
  });
}
