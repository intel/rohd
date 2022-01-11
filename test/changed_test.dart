/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// changed_test.dart
/// Unit tests for Logic change events
///
/// 2021 November 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    Simulator.reset();
  });

  test('single changed multiple injections', () async {
    var a = Logic();
    a.put(0);

    var b = Logic();
    b.put(0);

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
    var clk = SimpleClockGenerator(10).clk;
    var b = Logic();

    bool val = false;
    clk.negedge.listen((event) async {
      b.inject(val);
      val = !val;
    });

    var uniquePosedgeTimestamps = <int>{};
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
    var a = Logic();
    a.put(0);

    int numPosedges = 0;
    a.posedge.listen((event) {
      numPosedges += 1;
    });

    a.inject(1);

    await Simulator.run();

    expect(numPosedges, equals(1));
  });
}
