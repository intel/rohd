/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// benchmark.dart
/// Runs benchmarks and prints values.
///
/// 2022 September 28
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'pipeline_benchmark.dart';

void main() async {
  await PipelineBenchmark().report();
}
