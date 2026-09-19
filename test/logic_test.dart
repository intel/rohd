// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_test.dart
// Unit tests for `Logic` functionality.
//
// 2025 July 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('packed simple logic returns itself', () {
    final logic = Logic();
    expect(logic.packed, logic);
  });

  test('getRange on filled constants returns a constant', () {
    for (final fillValue in [
      LogicValue.zero,
      LogicValue.one,
      LogicValue.x,
      LogicValue.z,
    ]) {
      final range = Const(LogicValue.filled(8, fillValue)).getRange(2, 5);

      expect(range, isA<Const>());
      expect(range.value, LogicValue.filled(3, fillValue));
      expect(range.parentModule, isNull);
    }
  });

  test('getRange on mixed constants still uses BusSubset', () {
    final range = Const(LogicValue.ofString('10101010')).getRange(2, 5);

    expect(range, isNot(isA<Const>()));
    expect(range.parentModule, isA<BusSubset>());
  });
}
