/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_values_test.dart
/// Tests for LogicValues
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

//TODO: reversed looks broken
//TODO: add a test with x & 0 == 0
void main() {
  group('two input bitwise', () {
    test('and2', () {
      expect(LogicValues.fromString('01xz') & LogicValues.fromString('1111'),
          equals(LogicValues.fromString('01xx')));
      expect(
          LogicValues.filled(100, LogicValue.zero) &
              LogicValues.filled(100, LogicValue.one),
          equals(LogicValues.filled(100, LogicValue.zero)));
      expect(
          LogicValues.fromString('01xz' * 100) &
              LogicValues.fromString('1111' * 100),
          equals(LogicValues.fromString('01xx' * 100)));
    });
  });

  group('logic value', () {
    test('fromBool', () {
      expect(LogicValue.fromBool(true), equals(LogicValue.one));
      expect(LogicValue.fromBool(false), equals(LogicValue.zero));
      expect(LogicValues.fromBool(true), equals(LogicValues.fromString('1')));
      expect(LogicValues.fromBool(false), equals(LogicValues.fromString('0')));
    });
  });
}
