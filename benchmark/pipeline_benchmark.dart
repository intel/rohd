/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// pipeline_benchmark.dart
/// Benchmarking for pipeline simulation performance
///
/// 2022 September 28
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import '../test/pipeline_test.dart';

class PipelineBenchmark extends AsyncBenchmarkBase {
  late RVPipelineModule _rvPipelineModule;

  PipelineBenchmark() : super('Pipeline');

  @override
  Future<void> setup() async {
    _rvPipelineModule =
        RVPipelineModule(Logic(width: 8), Logic(), Logic(), Logic());
    await _rvPipelineModule.build();
  }

  @override
  Future<void> teardown() async {
    await Simulator.reset();
  }

  @override
  Future<void> run() async {
    // ideally there would be more vectors in here... just copy paste
    // from test for now
    final vectors = [
      Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
      Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
      Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
      Vector({'reset': 0, 'a': 1, 'validIn': 1, 'readyForOut': 1},
          {'validOut': 0}),
      Vector({'reset': 0, 'a': 2, 'validIn': 1, 'readyForOut': 1},
          {'validOut': 0}),
      Vector({'reset': 0, 'a': 3, 'validIn': 1, 'readyForOut': 1},
          {'validOut': 0}),
      Vector({'reset': 0, 'a': 4, 'validIn': 1, 'readyForOut': 1},
          {'validOut': 1, 'b': 4}),
      Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
          {'validOut': 1, 'b': 5}),
      Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
          {'validOut': 1, 'b': 6}),
      Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
          {'validOut': 1, 'b': 7}),
      Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
          {'validOut': 0}),
      Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
          {'validOut': 0}),
    ];
    await SimCompare.checkFunctionalVector(_rvPipelineModule, vectors,
        enableChecking: false);

    // sucks but this appears to be necessary since it runs 10x with
    // this package
    await Simulator.reset();
  }
}

Future<void> main() async {
  await PipelineBenchmark().report();
}
