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

// All logicvalues to support trying all possiblities
const allLv = [LogicValue.zero, LogicValue.one, LogicValue.x, LogicValue.z];

// shorten some names to make tests read better
final lv = LogicValues.fromString;
LogicValues large(LogicValue lv) => LogicValues.filled(100, lv);

void main() {
  group('two input bitwise', () {
    test('and2', () {
      // test z & 1 == x, rest unchanged
      expect(lv('01xz') & lv('1111'), equals(lv('01xx')));
      // Large filled test of * & 1
      for (final v in allLv) {
        expect(large(v) & large(LogicValue.one),
            equals(large(v & LogicValue.one)));
      }
      // Large logicValues test of &
      expect(lv('01xz' * 100) & lv('1111' * 100), equals(lv('01xx' * 100)));
      // test * & 0 = 0
      expect(lv('01xz') & lv('0000'), equals(lv('0000')));
      // try mixing .fromString with .filled
      expect(lv('01xz') & LogicValues.filled(4, LogicValue.zero),
          equals(LogicValues.filled(4, LogicValue.zero)));
    });
  });
  group('LogicValues Misc', () {
    test('reversed', () {
      expect(lv('01xz').reversed, equals(lv('zx10')));
      expect(lv('010').reversed, equals(lv('010')));
      // reverse large values
      expect(lv('01' * 100).reversed, equals(lv('10' * 100)));
      expect(lv('01xz' * 100).reversed, equals(lv('zx10' * 100)));
      // reverse filled
      for (final v in allLv) {
        expect(large(v).reversed, equals(large(v)));
      }
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
