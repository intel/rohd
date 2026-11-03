// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// clock_divider_test.dart
// Tests Sequential outputs used as downstream clock triggers.
//
// 2026 November 2
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _ClockDivider extends Module {
  /// The divided clock.
  Logic get clkOut => output('clkOut');

  _ClockDivider(Logic clkIn, Logic reset)
      : super(name: 'clockDivider', definitionName: 'ClockDivider') {
    clkIn = addInput('clkIn', clkIn);
    reset = addInput('reset', reset);
    final clkOut = addOutput('clkOut');

    Sequential.multi([
      clkIn,
      reset,
    ], [
      If(reset, then: [
        clkOut < 0,
      ], orElse: [
        clkOut < ~clkOut,
      ]),
    ]);
  }
}

class _ClockedCounter extends Module {
  /// The incrementing count.
  Logic get count => output('count');

  _ClockedCounter(Logic clk, Logic reset)
      : super(name: 'clockedCounter', definitionName: 'ClockedCounter') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    final count = addOutput('count', width: 8);
    final nextCount = count + Const(1, width: count.width);

    Sequential.multi([
      clk,
      reset,
    ], [
      If(reset, then: [
        count < 0,
      ], orElse: [
        count < nextCount,
      ]),
    ]);
  }
}

class _ClockDividerHarness extends Module {
  /// The divided clock exposed for checking.
  Logic get divided => output('divided');

  /// The counter driven by [divided].
  Logic get count => output('count');

  _ClockDividerHarness(Logic resetClocks, Logic resetCounters)
      : super(definitionName: 'ClockDividerHarness') {
    resetClocks = addInput('resetClocks', resetClocks);
    resetCounters = addInput('resetCounters', resetCounters);
    final clk = SimpleClockGenerator(10).clk;
    final divider = _ClockDivider(clk, resetClocks);
    final counter = _ClockedCounter(divider.clkOut, resetCounters);

    addOutput('divided') <= divider.clkOut;
    addOutput('count', width: counter.count.width) <= counter.count;
  }
}

class _JointClockAndResetHarness extends Module {
  /// The value captured by the derived-clock sequential block.
  Logic get captured => output('captured');

  _JointClockAndResetHarness(Logic clk, Logic releaseReset, Logic data)
      : super(definitionName: 'JointClockAndResetHarness') {
    clk = addInput('clk', clk);
    releaseReset = addInput('releaseReset', releaseReset);
    data = addInput('data', data);
    final derivedClk = Logic(name: 'derivedClk');
    final childReset = Logic(name: 'childReset');
    final captured = addOutput('captured');

    Sequential(clk, [
      If(
        releaseReset,
        then: [
          derivedClk < 1,
          childReset < 0,
        ],
        orElse: [
          derivedClk < 0,
          childReset < 1,
        ],
      ),
    ]);

    Sequential(
      derivedClk,
      reset: childReset,
      asyncReset: true,
      [
        captured < data,
      ],
    );
  }
}

void main() {
  tearDown(Simulator.reset);

  test('downstream counter captures a divided-clock edge in the same tick',
      () async {
    // Keep the counter in reset until the divider has first reached a known
    // low state, then check immediately after the divided rising edge.
    final resetClocks = Logic()..put(1);
    final resetCounters = Logic()..put(1);
    final dut = _ClockDividerHarness(resetClocks, resetCounters);
    await dut.build();

    Simulator.registerAction(12, () {
      resetClocks.put(0);
    });
    Simulator.registerAction(32, () {
      resetCounters.put(0);
    });
    Simulator.registerAction(36, () {
      expect(dut.divided.value, LogicValue.one);
      expect(
        dut.count.value,
        LogicValue.ofInt(1, dut.count.width),
        reason: 'The downstream Sequential must capture the divider edge '
            'during the tick in which it rises.',
      );
    });
    Simulator.registerAction(41, () {
      expect(
        dut.count.value,
        LogicValue.ofInt(1, dut.count.width),
        reason: 'The divided edge must not be replayed on the next tick.',
      );
    });
    Simulator.setMaxSimTime(45);

    await Simulator.run();
  });

  test('derived clock observes a jointly deasserted async reset', () async {
    final clk = Logic()..put(0);
    final releaseReset = Logic()..put(0);
    final data = Logic()..put(1);
    final dut = _JointClockAndResetHarness(clk, releaseReset, data);
    await dut.build();

    Simulator.registerAction(10, () {
      clk.put(1);
    });
    Simulator.registerAction(11, () {
      clk.put(0);
    });
    Simulator.registerAction(15, () {
      releaseReset.put(1);
    });
    Simulator.registerAction(20, () {
      clk.put(1);
    });
    Simulator.registerAction(21, () {
      expect(
        dut.captured.value,
        LogicValue.one,
        reason: 'The derived-clock Sequential must sample after its producer '
            'has deasserted the async reset.',
      );
    });
    Simulator.setMaxSimTime(22);

    await Simulator.run();
  });
}
