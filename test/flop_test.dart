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
  FlopTestModule(Logic a, {Logic? en, Logic? reset, dynamic resetValue})
      : super(name: 'floptestmodule') {
    a = addInput('a', a, width: a.width);

    if (en != null) {
      en = addInput('en', en);
    }

    if (reset != null) {
      reset = addInput('reset', reset);
    }

    if (resetValue != null && resetValue is Logic) {
      resetValue = addInput('resetValue', resetValue, width: a.width);
    }

    final y = addOutput('y', width: a.width);
    final clk = SimpleClockGenerator(10).clk;

    y <= flop(clk, a, en: en, reset: reset, resetValue: resetValue);
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
      SimCompare.checkIverilogVector(ftm, vectors);
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
      SimCompare.checkIverilogVector(ftm, vectors);
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
      SimCompare.checkIverilogVector(ftm, vectors);
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
      SimCompare.checkIverilogVector(ftm, vectors);
    });

    test('flop bus reset, no reset value', () async {
      final ftm = FlopTestModule(Logic(width: 8), reset: Logic());
      await ftm.build();
      final vectors = [
        Vector({'reset': 1}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 0}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      SimCompare.checkIverilogVector(ftm, vectors);
    });

    test('flop bus reset, const reset value', () async {
      final ftm = FlopTestModule(
        Logic(width: 8),
        reset: Logic(),
        resetValue: 3,
      );
      await ftm.build();
      final vectors = [
        Vector({'reset': 1}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 3}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      SimCompare.checkIverilogVector(ftm, vectors);
    });

    test('flop bus reset, logic reset value', () async {
      final ftm = FlopTestModule(
        Logic(width: 8),
        reset: Logic(),
        resetValue: Logic(width: 8),
      );
      await ftm.build();
      final vectors = [
        Vector({'reset': 1, 'resetValue': 5}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 5}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      SimCompare.checkIverilogVector(ftm, vectors);
    });

    test('flop bus no reset, const reset value', () async {
      final ftm = FlopTestModule(
        Logic(width: 8),
        resetValue: 9,
      );
      await ftm.build();
      final vectors = [
        Vector({}, {}),
        Vector({'a': 0xa5}, {}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      SimCompare.checkIverilogVector(ftm, vectors);
    });

    test('flop bus, enable, reset, const reset value', () async {
      final ftm = FlopTestModule(
        Logic(width: 8),
        en: Logic(),
        reset: Logic(),
        resetValue: 12,
      );
      await ftm.build();
      final vectors = [
        Vector({'reset': 1, 'en': 0}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 12}),
        Vector({}, {'y': 12}),
        Vector({'en': 1}, {'y': 12}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      SimCompare.checkIverilogVector(ftm, vectors);
    });
  });
}
