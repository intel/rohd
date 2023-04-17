/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// exercise_1_d_flip_flop.dart
/// A simple answer for d flip flop implementation based on chapter 7 bootcamp.
///
/// 2023 April 17
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class DFlipFlop extends Module {
  DFlipFlop(Logic data, Logic reset, Logic clk) {
    // declare input and output
    data = addInput(data.name, data);
    reset = addInput(reset.name, reset);
    clk = addInput('clk', clk);

    final q = addOutput('q');

    Sequential(clk, [
      If(reset, then: [
        q < Const(0)
      ], orElse: [
        q < data,
      ])
    ]);
  }

  Logic get q => output('q');
}

Future<void> main() async {
  test('should return results similar to truth table', () async {
    final clk = SimpleClockGenerator(10).clk;
    final data = Logic(name: 'data');
    final reset = Logic(name: 'reset');

    final dff = DFlipFlop(data, reset, clk);
    await dff.build();

    print(dff.generateSynth());

    data.inject(1);
    reset.inject(1);

    void printFlop([String message = '']) {
      print('@t=${Simulator.time}:\t'
          ' input=${data.value}, output '
          '=${dff.q.value.toString(includeWidth: false)}\t$message');
    }

    // Start the Simulator and give maximum simulation time
    Simulator.setMaxSimTime(100);

    unawaited(Simulator.run());

    WaveDumper(dff,
        outputPath: 'doc/tutorials/chapter_7/answers/d_flip_flop.vcd');

    printFlop('Before');

    await clk.nextPosedge;
    printFlop('First tick, set set to 0 and data to 1');
    reset.put(0);
    data.put(1);
    expect(dff.q.value.toInt(), equals(0));

    await clk.nextPosedge;
    printFlop('Second tick, set data to 0');
    data.put(0);
    expect(dff.q.value.toInt(), equals(1));

    await clk.nextPosedge;
    printFlop('Third tick, end simulation.');
    expect(dff.q.value.toInt(), equals(0));

    Simulator.endSimulation();
  });
}
