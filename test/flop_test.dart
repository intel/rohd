// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flop_test.dart
// Unit tests for flip flops
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class FlopTestModule extends Module {
  Logic get a => input('a');
  Logic get y => output('y');
  Logic get en => input('en');

  FlopTestModule(Logic a, {Logic? en}) : super(name: 'floptestmodule') {
    a = addInput('a', a, width: a.width);
    if (en != null) {
      en = addInput('en', en, width: en.width);
    }

    final y = addOutput('y', width: a.width);
    final clk = SimpleClockGenerator(10).clk;

    if (en != null) {
      y <= flop(clk, a, en: en);
    } else {
      y <= flop(clk, a);
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('flop bit', () async {
      final ftm = FlopTestModule(Logic());
      await ftm.build();
      final vectors = [
        Vector({'a': 0}, {}),
        Vector({'a': 1}, {'y': 0}),
        Vector({'a': 1}, {'y': 1}),
        Vector({'a': 0}, {'y': 1}),
        Vector({'a': 0}, {'y': 0}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
      // expect(true, true);
    });

    test('flop bit with enable', () async {
      final ftm = FlopTestModule(Logic(), en: Logic());
      await ftm.build();
      final vectors = [
        Vector({'a': 0, 'en': 1}, {}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 1}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 0}, {'y': 1}),
        Vector({'a': 0, 'en': 0}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 1}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 0, 'en': 0}, {'y': 1}),
        Vector({'a': 1, 'en': 0}, {'y': 1}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
      // expect(true, true);
    });

    test('flop bus', () async {
      final ftm = FlopTestModule(Logic(width: 8));
      await ftm.build();
      final vectors = [
        Vector({'a': 0}, {}),
        Vector({'a': 0xff}, {'y': 0}),
        Vector({'a': 0xaa}, {'y': 0xff}),
        Vector({'a': 0x55}, {'y': 0xaa}),
        Vector({'a': 0x1}, {'y': 0x55}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });

    test('flop bus with enable', () async {
      final ftm = FlopTestModule(Logic(width: 8), en: Logic());
      await ftm.build();
      final vectors = [
        Vector({'a': 0, 'en': 1}, {}),
        Vector({'a': 0xff, 'en': 1}, {'y': 0}),
        Vector({'a': 0xaa, 'en': 1}, {'y': 0xff}),
        Vector({'a': 0x55, 'en': 1}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x55}),
        Vector({'a': 0, 'en': 1}, {'y': 0x1}),
        Vector({'a': 0xff, 'en': 1}, {'y': 0}),
        Vector({'a': 0xaa, 'en': 1}, {'y': 0xff}),
        Vector({'a': 0x55, 'en': 0}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 0}, {'y': 0xaa}),
        Vector({'a': 0x55, 'en': 1}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x55}),
        Vector({'a': 0x55, 'en': 0}, {'y': 0x1}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x1}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
  });
}
