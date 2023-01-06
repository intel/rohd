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
  static const _numExtraOutputs = 50;

  _ModuleToDump(Logic d, Logic clk) {
    d = addInput('d', d);

    final q = addOutput('q');

    for (var i = 0; i < _numExtraOutputs; i++) {
      addOutput('i$i') <= FlipFlop(clk, ~output('i$i')).q;
    }

    q <= FlipFlop(clk, d).q;
  }
}

class WaveDumpBenchmark extends AsyncBenchmarkBase {
  late _ModuleToDump _mod;
  late Logic _clk;

  static const _maxSimTime = 1000;

  static const _vcdTemporaryPath = 'tmp_test/wave_dump_benchmark.vcd';

  WaveDumpBenchmark() : super('WaveDump');

  @override
  Future<void> setup() async {
    Simulator.setMaxSimTime(_maxSimTime);
  }

  @override
  Future<void> teardown() async {
    if (File(_vcdTemporaryPath).existsSync()) {
      File(_vcdTemporaryPath).deleteSync();
    }
  }

  @override
  Future<void> run() async {
    _clk = SimpleClockGenerator(10).clk;
    _mod = _ModuleToDump(Logic(), _clk);
    await _mod.build();

    WaveDumper(_mod, outputPath: _vcdTemporaryPath);

    await Simulator.run();

    assert(Simulator.time == _maxSimTime, 'sim should run through end');

    await Simulator.reset();
    Simulator.setMaxSimTime(_maxSimTime);
  }
}

Future<void> main() async {
  await WaveDumpBenchmark().report();
}
