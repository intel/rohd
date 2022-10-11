/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// changed_test.dart
/// Unit tests for Logic change events
///
/// 2021 November 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Simulator.reset);

  test('single changed multiple injections', () async {
    final a = Logic()..put(0);

    final b = Logic()..put(0);

    var numChangesDetected = 0;

    a.changed.listen((event) {
      numChangesDetected++;
    });

    a.posedge.listen((event) {
      b.inject(1);
    });

    Simulator.registerAction(10, () => a.put(1));

    await Simulator.run();

    expect(numChangesDetected, equals(1));
  });

  test('clk edge counter', () async {
    final clk = SimpleClockGenerator(10).clk;
    final b = Logic();

    var val = false;
    clk.negedge.listen((event) async {
      b.inject(val);
      val = !val;
    });

    final uniquePosedgeTimestamps = <int>{};
    var count = 0;
    clk.posedge.listen((event) {
      uniquePosedgeTimestamps.add(Simulator.time);
      count++;
    });

    Simulator.setMaxSimTime(100);
    await Simulator.run();

    expect(count, equals(uniquePosedgeTimestamps.length));
  });

  test('injection triggers edge', () async {
    final a = Logic()..put(0);

    var numPosedges = 0;
    a.posedge.listen((event) {
      numPosedges += 1;
    });

    a.inject(1);

    await Simulator.run();

    expect(numPosedges, equals(1));
  });

  test('injection triggers flop', () async {
    final baseClk = SimpleClockGenerator(10).clk;

    final clk = Logic();
    final d = Logic();

    final q = FlipFlop(clk, d).q;

    var qHadPosedge = false;

    Simulator.setMaxSimTime(100);

    unawaited(q.nextPosedge.then((value) {
      qHadPosedge = true;
    }));

    unawaited(Simulator.run());

    await baseClk.nextPosedge;
    clk.inject(0);
    d.inject(0);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.zero));
    clk.inject(0);
    d.inject(1);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.one));

    await Simulator.simulationEnded;

    expect(qHadPosedge, equals(true));
  });
}
