/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// wave_dump_benchmark.dart
/// Benchmarking for wave dumping
///
/// 2023 January 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class _ModuleToDump extends Module {
  _ModuleToDump(Logic d) {
    d = addInput('d', d);

    final q = addOutput('q');

    final clk = SimpleClockGenerator(10).clk;

    for (var i = 0; i < 100; i++) {
      addOutput('i$i') <= FlipFlop(clk, ~output('i$i')).q;
    }

    q <= FlipFlop(clk, d).q;
  }
}

class WaveDumpBenchmark extends AsyncBenchmarkBase {
  late _ModuleToDump _mod;

  static const _vcdTemporaryPath = 'tmp_test/wave_dump_benchmark.vcd';

  WaveDumpBenchmark() : super('WaveDump');

  @override
  Future<void> setup() async {
    Simulator.setMaxSimTime(1000);

    _mod = _ModuleToDump(Logic());
    await _mod.build();
  }

  @override
  Future<void> teardown() async {
    File(_vcdTemporaryPath).deleteSync();
    await Simulator.reset();
  }

  @override
  Future<void> run() async {
    WaveDumper(_mod, outputPath: _vcdTemporaryPath);

    await Simulator.run();

    await Simulator.reset();
  }
}

Future<void> main() async {
  await WaveDumpBenchmark().report();
}
