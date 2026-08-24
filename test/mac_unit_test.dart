// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mac_unit_test.dart
// Tests for the filter-bank multiply-accumulate example.
//
// 2026 August 24
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/filter_bank/mac_unit.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('disabled pipeline holds its result and intermediate stages', () async {
    const dataWidth = 8;
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic();
    final enable = Logic();
    final sample = Logic(width: dataWidth);
    final coefficient = Logic(width: dataWidth);
    final accumulator = Logic(width: dataWidth);
    final dut = MacUnit(
      sample,
      coefficient,
      accumulator,
      clk,
      reset,
      enable,
      dataWidth: dataWidth,
    );
    await dut.build();

    reset.inject(1);
    enable.inject(0);
    sample.inject(0);
    coefficient.inject(0);
    accumulator.inject(0);
    Simulator.setMaxSimTime(200);
    unawaited(Simulator.run());

    await clk.nextPosedge;
    reset.inject(0);
    enable.inject(1);
    sample.inject(3);
    coefficient.inject(4);
    accumulator.inject(5);
    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextNegedge;
    expect(dut.result.value.toInt(), 17);

    enable.inject(0);
    sample.inject(7);
    coefficient.inject(8);
    accumulator.inject(9);
    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextNegedge;
    expect(
      dut.result.value.toInt(),
      17,
      reason: 'Both pipeline stages must hold while enable is low.',
    );

    enable.inject(1);
    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextNegedge;
    expect(dut.result.value.toInt(), 65);

    await Simulator.endSimulation();
  });
}
