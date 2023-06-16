// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// previous_value_Test.dart
// Tests for Logic.previousValue
//
// 2023 June 16
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('sample on flop with listen', () async {
    final clk = SimpleClockGenerator(10).clk;

    final a = Logic()..put(0);

    final b = flop(clk, a);
    final c = flop(clk, b);

    Simulator.registerAction(11, () => a.put(1));

    c.previousValue;

    clk.posedge.listen((event) {
      if (Simulator.time == 25) {
        expect(c.previousValue!.toInt(), 0);
        expect(c.value.toInt(), 1);
      }
    });

    Simulator.setMaxSimTime(200);
    await Simulator.run();
  });

  test('sample on flop with await', () async {
    final clk = SimpleClockGenerator(10).clk;

    final a = Logic()..put(0);

    final b = flop(clk, a);
    final c = flop(clk, b);

    Simulator.registerAction(11, () => a.put(1));

    c.previousValue;

    Future<void> clkLoop() async {
      while (!Simulator.simulationHasEnded) {
        await clk.nextPosedge;
        if (Simulator.time == 25) {
          expect(c.previousValue!.toInt(), 0);
          expect(c.value.toInt(), 1);
        }
      }
    }

    unawaited(clkLoop());

    Simulator.setMaxSimTime(200);
    await Simulator.run();
  });
}
