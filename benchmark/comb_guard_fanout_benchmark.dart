// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// comb_guard_fanout_benchmark.dart
// Benchmarking for many `Combinational` listeners on the same signals, leading
// to many `guard`s and subscription cancels in signal listeners.
//
// 2023 April 21
// Author: Max Korbel <max.korbel@intel.com>

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class CombGuardFanout extends Module {
  CombGuardFanout(Logic a,
      {int numStatements = 10, int numCombinationals = 100}) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);

    // final sxi = List.generate(numStatements, (index) => Logic(width: a.width));
    final sxi = <Logic>[a];

    for (var i = 1; i < numStatements; i++) {
      sxi.add(listeners(sxi[i - 1]));
    }

    for (var c = 0; c < numCombinationals; c++) {
      Combinational([
        for (var i = 1; i < numStatements; i++)
          Logic(width: a.width) < sxi[i - 1],
      ]);
    }
  }

  Logic listeners(
    Logic a, {
    int fanout = 5,
  }) {
    final toReturn = a + 1;
    for (var i = 0; i < fanout; i++) {
      Logic(width: a.width) <= ~toReturn;
    }
    return toReturn;
  }
}

class CombGuardFanoutBenchmark extends AsyncBenchmarkBase {
  final int numPuts;
  CombGuardFanoutBenchmark({this.numPuts = 100})
      : super('CombGuardFanoutBenchmark');

  @override
  Future<void> teardown() async {
    await Simulator.reset();
  }

  CombGuardFanout? mod;
  final Logic a = Logic(width: 8);

  @override
  Future<void> setup() async {
    mod = CombGuardFanout(a);
    await mod!.build();
  }

  @override
  Future<void> run() async {
    for (var i = 0; i < numPuts; i++) {
      a.put(i);
    }
  }
}

Future<void> main() async {
  await CombGuardFanoutBenchmark().report();
  print('done');
}
