// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// clkgen_test.dart
// Tests for the simple clock generator
//
// 2026 September 21
// Author: Shubham Padkonde <shubhampadkonde12@gmail.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// Collects the times of the first [count] positive edges of a clock with
/// [clockPeriod].
Future<List<int>> posedgeTimes(int clockPeriod, {int count = 4}) async {
  await Simulator.reset();

  final clk = SimpleClockGenerator(clockPeriod).clk;
  final times = <int>[];

  clk.posedge.listen((_) {
    times.add(Simulator.time);
    if (times.length == count) {
      unawaited(Simulator.endSimulation());
    }
  });

  Simulator.setMaxSimTime(clockPeriod * (count + 2));
  await Simulator.run();

  return times;
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('generates the requested period', () {
    for (final clockPeriod in [2, 4, 10]) {
      test('of $clockPeriod', () async {
        final times = await posedgeTimes(clockPeriod);

        expect(times.length, 4);
        for (var i = 1; i < times.length; i++) {
          expect(times[i] - times[i - 1], clockPeriod,
              reason: 'positive edges should be $clockPeriod apart');
        }
      });
    }
  });

  group('rejects a period it cannot generate', () {
    // A period below 2 has a half period of 0, which schedules both edges in
    // the same time unit and hangs the simulation.
    for (final clockPeriod in [-2, -1, 0, 1]) {
      test('of $clockPeriod', () {
        expect(() => SimpleClockGenerator(clockPeriod),
            throwsA(isA<IllegalConfigurationException>()));
      });
    }

    // An odd period is rounded down by the half period, so the generated
    // clock would silently run at a different frequency than requested.
    for (final clockPeriod in [3, 5, 11]) {
      test('of $clockPeriod', () {
        expect(() => SimpleClockGenerator(clockPeriod),
            throwsA(isA<IllegalConfigurationException>()));
      });
    }
  });
}
