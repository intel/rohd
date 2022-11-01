/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// clock_divider_test.dart
/// Unit tests for a clock divider.
///
/// 2022 November 1
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import '../example/example.dart' as sync_reset;
import 'counter_test.dart' as async_reset;

class ClockDivider extends Module {
  Logic get clkOut => output('clkOut');
  ClockDivider(Logic clkIn, Logic reset) : super(name: 'clockDivider') {
    clkIn = addInput('clkIn', clkIn);
    reset = addInput('reset', reset);
    final clkOut = addOutput('clkOut');

    Sequential(clkIn, [
      If(
        reset,
        then: [clkOut < 0],
        orElse: [clkOut < ~clkOut],
      ),
    ]);
  }
}

class TwoCounters extends Module {
  TwoCounters(Logic resetClks, Logic resetCounters, {required bool syncReset}) {
    resetClks = addInput('resetClks', resetClks);
    resetCounters = addInput('resetCounters', resetCounters);

    final clk = SimpleClockGenerator(10).clk;
    final clkDiv = ClockDivider(clk, resetClks).clkOut;

    addOutput('cntFast', width: 8) <=
        (syncReset
            ? sync_reset.Counter(Const(1), resetCounters, clk,
                    name: 'fastCounter')
                .val
            : async_reset.Counter(Const(1), resetCounters,
                    clkOverride: clk, name: 'fastCounter')
                .val);
    addOutput('cntSlow', width: 8) <=
        (syncReset
            ? sync_reset.Counter(Const(1), resetCounters, clkDiv,
                    name: 'slowCounter')
                .val
            : async_reset.Counter(Const(1), resetCounters,
                    clkOverride: clkDiv, name: 'slowCounter')
                .val);
  }
}

void main() {
  tearDown(Simulator.reset);
  group('clock divider', () {
    final vectors = [
      Vector({'resetClks': 1, 'resetCounters': 1}, {}),
      Vector({'resetClks': 0, 'resetCounters': 1}, {}),
      Vector({'resetClks': 0, 'resetCounters': 1}, {}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 0, 'cntFast': 0}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 1, 'cntFast': 1}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 1, 'cntFast': 2}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 2, 'cntFast': 3}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 2, 'cntFast': 4}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 3, 'cntFast': 5}),
      Vector(
          {'resetClks': 0, 'resetCounters': 0}, {'cntSlow': 3, 'cntFast': 6}),
    ];
    final signalToWidthMap = {'cntSlow': 8, 'cntFast': 8};

    test('sync reset', () async {
      final mod = TwoCounters(Logic(), Logic(), syncReset: true);
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(
          mod.generateSynth(), mod.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('async reset', () async {
      final mod = TwoCounters(Logic(), Logic(), syncReset: false);
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(
          mod.generateSynth(), mod.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });
  });
}
