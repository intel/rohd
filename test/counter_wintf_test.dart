/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// counter_wintf_test.dart
/// Unit tests for a basic counter with an interface
///
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'dart:developer';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum CounterDirection { inward, outward }

class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');
  Logic get resetVal => port('resetVal');

  final int width;
  CounterInterface(this.width) {
    setPorts([Port('en'), Port('reset')], [CounterDirection.inward]);

    setPorts([
      Port('val', width),
    ], [
      CounterDirection.outward
    ]);
  }
}

class Counter extends Module {
  late final CounterInterface intf;
  late bool resetRoot;
  Counter(CounterInterface intf,
      {this.resetRoot = false, bool withResetVal = false}) {
    this.intf = CounterInterface(intf.width)
      ..connectIO(this, intf,
          inputTags: {CounterDirection.inward},
          outputTags: {CounterDirection.outward});

    // this should do nothing
    this.intf.connectIO(this, intf);

    // ignore: avoid_print
    print('message $withResetVal');
    if (withResetVal) {
      _buildLogic();
    } else {
      _buildResetValLogic();
    }
  }
  void _buildResetValLogic() {
    final nextVal = Logic(name: 'nextVal', width: intf.width);
    final enVal = Logic(name: 'enResetVal', width: 8);
    enVal < 1;
    final resetValues = <Logic, Logic>{intf.en: enVal};

    nextVal <= intf.val + 1;
    Sequential(
        SimpleClockGenerator(10).clk,
        [
          If(intf.en, then: [intf.val < nextVal])
        ],
        reset: intf.reset,
        resetValues: resetValues);
  }

  void _buildLogic() {
    final nextVal = Logic(name: 'nextVal', width: intf.width);

    nextVal <= intf.val + 1;

    if (resetRoot) {
      Sequential(
          SimpleClockGenerator(10).clk,
          [
            If(intf.en, then: [intf.val < nextVal])
          ],
          reset: intf.reset);
    } else {
      Sequential(SimpleClockGenerator(10).clk, [
        If(intf.reset, then: [
          intf.val < 0
        ], orElse: [
          If(intf.en, then: [intf.val < nextVal])
        ])
      ]);
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('counter', () async {
      final mod = Counter(CounterInterface(8));
      await mod.build();
      final vectors = [
        Vector({'en': 0, 'reset': 1}, {}),
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
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });
  });
  test('resetFlipflop from root w/o resetVal', () async {
    final mod =
        Counter(CounterInterface(8), resetRoot: true, withResetVal: true);
    await mod.build();
    final vectors = [
      Vector({'en': 0, 'reset': 1}, {}),
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
      Vector({'en': 0, 'reset': 0}, {'val': 5}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('resetFlipflop from root w/ resetVal', () async {
    final mod =
        Counter(CounterInterface(8), resetRoot: true, withResetVal: true);
    await mod.build();
    final vectors = [
      Vector({'en': 0, 'reset': 1}, {}),
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
      Vector({'en': 0, 'reset': 0}, {'val': 5}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
