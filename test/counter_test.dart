/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// counter_test.dart
/// Unit tests for a basic counter
///
/// 2021 May 10
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class Counter extends Module {
  final int width;
  Logic get val => output('val');
  Counter(Logic en, Logic reset, {this.width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);

    final val = addOutput('val', width: width);

    final nextVal = Logic(name: 'nextVal', width: width);

    nextVal <= val + 1;

    Sequential.multi([
      SimpleClockGenerator(10).clk,
      reset
    ], [
      If(reset, then: [
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('counter', () async {
      final reset = Logic();
      final counter = Counter(Logic(), reset);
      await counter.build();
      // WaveDumper(counter);

      unawaited(reset.nextPosedge
          .then((value) => expect(counter.val.value.toInt(), equals(0))));

      final vectors = [
        Vector({'en': 0, 'reset': 0}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];
      await SimCompare.checkFunctionalVector(counter, vectors);
      final simResult = SimCompare.iverilogVector(counter, vectors);
      expect(simResult, equals(true));
    });
  });
}
