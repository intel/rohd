// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// many_submodules_benchmark.dart
// A benchmarking test for a large number of submodules.
//
// 2024 June 12
// Author: Max Korbel <max.korbel@intel.com>

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class ManySubmodulesModule extends Module {
  late final Logic y;
  ManySubmodulesModule(Logic x, {int numSubModules = 0}) {
    x = addInput('x', x);
    y = addOutput('y');

    var intermediate = x;

    for (var i = 0; i < numSubModules; i++) {
      intermediate = ManySubmodulesModule(intermediate).y;
    }

    y <= intermediate;
  }
}

class ManySubmodulesBenchmark extends AsyncBenchmarkBase {
  ManySubmodulesBenchmark() : super('ManySubmodules');

  @override
  Future<void> run() async {
    final dut = ManySubmodulesModule(Logic(), numSubModules: 10000);
    await dut.build();
    dut.generateSynth();
  }
}

Future<void> main() async {
  await ManySubmodulesBenchmark().report();
}
