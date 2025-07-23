// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// counter_wintf_test.dart
// Unit tests for a basic counter with an interface
//
// 2021 May 25
// Author: Max Korbel <max.korbel@intel.com>

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
    setPorts(
        [Logic.port('en'), Logic.port('reset')], [CounterDirection.inward]);

    setPorts([
      Logic.port('val', width),
    ], [
      CounterDirection.outward
    ]);
  }

  @override
  CounterInterface clone() => CounterInterface(width);
}

class Counter extends Module {
  late final CounterInterface intf;
  Counter(CounterInterface intf,
      {bool useBuiltInSequentialReset = false, int resetValue = 0}) {
    this.intf = CounterInterface(intf.width)
      ..connectIO(this, intf,
          inputTags: {CounterDirection.inward},
          outputTags: {CounterDirection.outward});

    // this should do nothing
    this.intf.connectIO(this, intf);

    final nextVal = Logic(name: 'nextVal', width: intf.width);
    nextVal <= intf.val + 1;

    if (useBuiltInSequentialReset) {
      _buildResetValLogic(nextVal, resetValue: resetValue);
    } else {
      _buildLogic(nextVal);
    }
  }
  void _buildResetValLogic(Logic nextVal, {int resetValue = 0}) {
    final resetValues = <Logic, Logic>{intf.val: Const(resetValue, width: 8)};
    Sequential(
        SimpleClockGenerator(10).clk,
        [
          If(intf.en, then: [intf.val < nextVal])
        ],
        reset: intf.reset,
        resetValues: resetValues);
  }

  void _buildLogic(Logic nextVal) {
    Sequential(SimpleClockGenerator(10).clk, [
      If(intf.reset, then: [
        intf.val < 0
      ], orElse: [
        If(intf.en, then: [intf.val < nextVal])
      ])
    ]);
  }
}

Future<void> moduleTest(Counter mod) async {
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
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('counter', () async {
      final mod = Counter(CounterInterface(8));
      await moduleTest(mod);
    });
  });

  test('resetFlipflop from root w/o resetVal', () async {
    final mod = Counter(CounterInterface(8), useBuiltInSequentialReset: true);
    await moduleTest(mod);
  });

  test('resetFlipflop from root w/ resetVal', () async {
    final mod = Counter(CounterInterface(8),
        useBuiltInSequentialReset: true, resetValue: 3);
    await mod.build();
    final vectors = [
      Vector({'en': 0, 'reset': 1}, {}),
      Vector({'en': 0, 'reset': 1}, {'val': 3}),
      Vector({'en': 1, 'reset': 1}, {'val': 3}),
      Vector({'en': 1, 'reset': 0}, {'val': 3}),
      Vector({'en': 1, 'reset': 0}, {'val': 4}),
      Vector({'en': 1, 'reset': 0}, {'val': 5}),
      Vector({'en': 1, 'reset': 0}, {'val': 6}),
      Vector({'en': 0, 'reset': 0}, {'val': 7}),
      Vector({'en': 0, 'reset': 0}, {'val': 7}),
      Vector({'en': 1, 'reset': 0}, {'val': 7}),
      Vector({'en': 0, 'reset': 0}, {'val': 8}),
      Vector({'en': 0, 'reset': 0}, {'val': 8}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('interface ports dont get doubled up', () async {
    final mod = Counter(CounterInterface(8));
    await mod.build();
    final sv = mod.generateSynth();

    expect(!sv.contains('en_0'), true);
  });
}
