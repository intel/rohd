/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// benchmark_test.dart
/// Tests that run benchmarks to make sure they don't break.
///
/// 2022 September 28
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:test/test.dart';

import '../benchmark/logic_value_of_benchmark.dart';
import '../benchmark/pipeline_benchmark.dart';

void main() {
  test('pipeline benchmark', () async {
    await PipelineBenchmark().measure();
  });

  test('logic value of benchmark', () async {
    await LogicValueOfBenchmark().measure();
  });
}
