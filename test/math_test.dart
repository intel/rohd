/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// math_test.dart
/// Unit tests for math-related operations
///
/// 2021 May 21
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class MathTestModule extends Module {
  final int c;

  MathTestModule(Logic a, Logic b, {this.c = 5})
      : super(name: 'gatetestmodule') {
    if (a.width != b.width) {
      throw Exception('a and b must be same width');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aPlusB = addOutput('a_plus_b', width: a.width);
    final aMinusB = addOutput('a_minus_b', width: a.width);
    final aTimesB = addOutput('a_times_b', width: a.width);
    final aDividedByB = addOutput('a_dividedby_b', width: a.width);
    final aModuloB = addOutput('a_modulo_b', width: a.width);
    final aModuloConst = addOutput('a_modulo_const', width: a.width);

    final aPlusConst = addOutput('a_plus_const', width: a.width);
    final aMinusConst = addOutput('a_minus_const', width: a.width);
    final aTimesConst = addOutput('a_times_const', width: a.width);
    final aDividedByConst = addOutput('a_dividedby_const', width: a.width);

    final aSlB = addOutput('a_sl_b', width: a.width);
    final aSrlB = addOutput('a_srl_b', width: a.width);
    final aSraB = addOutput('a_sra_b', width: a.width);

    final aSlConst = addOutput('a_sl_const', width: a.width);
    final aSrlConst = addOutput('a_srl_const', width: a.width);
    final aSraConst = addOutput('a_sra_const', width: a.width);

    aPlusB <= a + b;
    aMinusB <= a - b;
    aTimesB <= a * b;
    aDividedByB <= a / b;
    aModuloB <= a % b;
    aModuloConst <= a % c;

    aPlusConst <= a + c;
    aMinusConst <= a - c;
    aTimesConst <= a * c;
    aDividedByConst <= a / c;

    aSlB <= a << b;
    aSrlB <= a >>> b;
    aSraB <= a >> b;

    aSlConst <= a << c;
    aSrlConst <= a >>> c;
    aSraConst <= a >> c;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    Future<void> runMathVectors(List<Vector> vectors) async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    }

    test('addition', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
        Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
        Vector({'a': 6}, {'a_plus_const': 11}),
        // Vector({'a': -6, 'b': 7}, {'a_plus_b': 1}),
        // Vector({'a': -6, 'b': 2}, {'a_plus_b': -4}),
      ]);
    });

    test('subtraction', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_minus_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_minus_b': 1}),
        Vector({'a': 0xff, 'b': 0xff}, {'a_minus_b': 0}),
        Vector({'a': 12, 'b': 5}, {'a_minus_b': 7}),
        Vector({'a': 6}, {'a_minus_const': 1}),
      ]);
    });

    test('multiplication', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_times_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_times_b': 1}),
        Vector({'a': 3, 'b': 4}, {'a_times_b': 12}),
        Vector({'a': 6}, {'a_times_const': 30}),
      ]);
    });

    test('division', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 5, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 9, 'b': 3}, {'a_dividedby_b': 3}),
        Vector({'a': 6}, {'a_dividedby_const': 1}),
      ]);
    });

    test('modulo', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_modulo_b': 0}),
        Vector({'a': 5, 'b': 2}, {'a_modulo_b': 1}),
        Vector({'a': 9, 'b': 3}, {'a_modulo_b': 0}),
        Vector({'a': 11}, {'a_modulo_const': 1})
      ]);
    });

    test('shift left', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_sl_b': 0xf}),
        Vector({'a': 0xf, 'b': 2}, {'a_sl_b': 0xf << 2}),
        Vector({'a': 0x2}, {'a_sl_const': 0x2 << 5}),
      ]);
    });

    test('shift right logical', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_srl_b': 0xf}),
        Vector({'a': 0xff, 'b': 2}, {'a_srl_b': 0x3f}),
        Vector({'a': bin('11000000')}, {'a_srl_const': bin('00000110')}),
      ]);
    });

    test('shift right arithmetic', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_sra_b': 0xf}),
        Vector({'a': 0xfe, 'b': 2}, {'a_sra_b': 0xff}),
        Vector({'a': bin('11000000')}, {'a_sra_const': bin('11111110')}),
      ]);
    });
  });
}
