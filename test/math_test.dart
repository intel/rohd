/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// math_test.dart
/// Unit tests for bus-related operations
///
/// 2021 May 21
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class MathTestModule extends Module {
  Logic get a => input('a');
  Logic get b => input('b');

  Logic get aPlusB => output('a_plus_b');
  Logic get aMinusB => output('a_minus_b');
  Logic get aTimesB => output('a_times_b');
  Logic get aDividedByB => output('a_dividedby_b');
  Logic get aModuloB => output('a_modulo_b');

  Logic get aPlusConst => output('a_plus_const');
  Logic get aMinusConst => output('a_minus_const');
  Logic get aTimesConst => output('a_times_const');
  Logic get aDividedByConst => output('a_dividedby_const');

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

    final aPlusConst = addOutput('a_plus_const', width: a.width);
    final aMinusConst = addOutput('a_minus_const', width: a.width);
    final aTimesConst = addOutput('a_times_const', width: a.width);
    final aDividedByConst = addOutput('a_dividedby_const', width: a.width);

    aPlusB <= a + b;
    aMinusB <= a - b;
    aTimesB <= a * b;
    aDividedByB <= a / b;
    aModuloB <= a % b;

    aPlusConst <= a + c;
    aMinusConst <= a - c;
    aTimesConst <= a * c;
    aDividedByConst <= a / c;
  }
}

void main() {
  tearDown(Simulator.reset);

  group('simcompare', () {
    test('addition', () async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
        Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
        Vector({'a': 6}, {'a_plus_const': 11}),
        // Vector({'a': -6, 'b': 7}, {'a_plus_b': 1}),
        // Vector({'a': -6, 'b': 2}, {'a_plus_b': -4}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm, gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('subtraction', () async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_minus_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_minus_b': 1}),
        Vector({'a': 0xff, 'b': 0xff}, {'a_minus_b': 0}),
        Vector({'a': 12, 'b': 5}, {'a_minus_b': 7}),
        Vector({'a': 6}, {'a_minus_const': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm, gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('multiplication', () async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_times_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_times_b': 1}),
        Vector({'a': 3, 'b': 4}, {'a_times_b': 12}),
        Vector({'a': 6}, {'a_times_const': 30}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm, gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('division', () async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 5, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 9, 'b': 3}, {'a_dividedby_b': 3}),
        Vector({'a': 6}, {'a_dividedby_const': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm, gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('modulo', () async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_modulo_b': 0}),
        Vector({'a': 5, 'b': 2}, {'a_modulo_b': 1}),
        Vector({'a': 9, 'b': 3}, {'a_modulo_b': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm, gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });
  });
}
