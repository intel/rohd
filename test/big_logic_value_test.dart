/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
///
/// bigint_test.dart
/// Test of very wide bitvector comparison failure
///

import 'dart:math';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('crash compare', () {
    final input = Const(BigInt.from(2).pow(128), width: 129);
    final output = Logic();
    Combinational([
      IfBlock([
        Iff(input.getRange(0, 128) > BigInt.from(0),
            [output < Const(1, width: 1)]),
        Else([output < Const(0, width: 1)]),
      ])
    ]);
  });
  test('bad compare', () {
    const i = 64;
    final input = Const(BigInt.from(1) << (i - 1), width: i);
    final output = Logic();
    Combinational([
      IfBlock([
        Iff(input > BigInt.from(0), [output < Const(1, width: 1)]),
        Else([output < Const(0, width: 1)]),
      ])
    ]);
    final b = ~input.eq(0);
    expect(output.value, equals(b.value));
  });
}
