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

import '../benchmark/byte_enable_benchmark.dart';
import '../benchmark/comb_guard_fanout_benchmark.dart';
import '../benchmark/logic_value_of_benchmark.dart';
import '../benchmark/many_seq_and_comb_benchmark.dart';
import '../benchmark/pipeline_benchmark.dart';
import '../benchmark/wave_dump_benchmark.dart';

void main() {
  test('pipeline benchmark', () async {
    await PipelineBenchmark().measure();
  });

  test('logic value of benchmark', () {
    LogicValueOfBenchmark().measure();
  });

  test('byte enable benchmark', () {
    ByteEnableBenchmark().measure();
  });

  test('waveform benchmark', () async {
    await WaveDumpBenchmark().measure();
  });

  group('many seq and comb benchmark', () {
    for (final connectionType in ManySeqAndCombCombConnectionType.values) {
      test(connectionType.name, () async {
        await ManySeqAndCombBenchmark(connectionType).measure();
      });
    }
  });

  test('comb guard fanout benchmark', () async {
    await CombGuardFanoutBenchmark().measure();
  });
}
