/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// benchmark.dart
/// Runs benchmarks and prints values.
///
/// 2022 September 28
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'byte_enable_benchmark.dart';
import 'logic_value_of_benchmark.dart';
import 'pipeline_benchmark.dart';
import 'wave_dump_benchmark.dart';

void main() async {
  await PipelineBenchmark().report();
  LogicValueOfBenchmark().report();
  ByteEnableBenchmark().report();
  await WaveDumpBenchmark().report();
}
