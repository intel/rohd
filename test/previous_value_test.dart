// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// previous_value_test.dart
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

  test('discarded wires do not retain simulator lifecycle callbacks', () async {
    // Install the shared lifecycle listener outside each counting zone.
    Logic();
    final callbacksByGeneration = List<int>.filled(3, 0);

    Zone countingZone(int generation) =>
        Zone.current.fork(specification: ZoneSpecification(
          runUnary: <R, T>(
            self,
            parent,
            zone,
            R Function(T) callback,
            argument,
          ) {
            if (Simulator.phase == SimulatorPhase.beforeTick) {
              callbacksByGeneration[generation]++;
            }
            return parent.runUnary(zone, callback, argument);
          },
        ));

    for (var generation = 0;
        generation < callbacksByGeneration.length;
        generation++) {
      final active = countingZone(generation)
          .run(() => List.generate(8, (_) => Logic()..put(0)));

      callbacksByGeneration.fillRange(0, callbacksByGeneration.length, 0);
      Simulator.registerAction(Simulator.time + 1, () {});
      await Simulator.tick();

      expect(
        active.every((signal) => signal.previousValue == signal.value),
        isTrue,
        reason: 'Active wires must still capture their pre-tick values.',
      );
      expect(
        callbacksByGeneration,
        everyElement(0),
        reason: 'Wire lifecycle callbacks must not accumulate by elaboration '
            'generation.',
      );
      active.clear();
    }
  });

  test('sample on flop with listen', () async {
    final clk = SimpleClockGenerator(10).clk;

    final a = Logic()..put(0);

    final b = flop(clk, a);
    final c = flop(clk, b);

    Simulator.registerAction(11, () => a.put(1));

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
