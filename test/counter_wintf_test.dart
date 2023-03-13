/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// counter_wintf_test.dart
/// Unit tests for a basic counter with an interface
///
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum CounterDirection { inward, outward }

class CounterInterface extends Interface<CounterDirection> {
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');

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
  Counter(CounterInterface intf) {
    this.intf = CounterInterface(intf.width)
      ..connectIO(this, intf,
          inputTags: {CounterDirection.inward},
          outputTags: {CounterDirection.outward});

    // this should do nothing
    this.intf.connectIO(this, intf);

    _buildLogic();
  }

  void _buildLogic() {
    final nextVal = Logic(name: 'nextVal', width: intf.width);

    nextVal <= intf.val + 1;

    Sequential(SimpleClockGenerator(10).clk, [
      If(intf.reset, then: [
        intf.val < 0
      ], orElse: [
        If(intf.en, then: [intf.val < nextVal])
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
}
