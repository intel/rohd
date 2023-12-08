// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// benchmark_test.dart
// Tests that run benchmarks to make sure they don't break.
//
// 2022 September 28
// Author: Max Korbel <max.korbel@intel.com>

import 'package:test/test.dart';

import '../benchmark/byte_enable_benchmark.dart';
import '../benchmark/comb_guard_fanout_benchmark.dart';
import '../benchmark/logic_value_of_benchmark.dart';
import '../benchmark/many_seq_and_comb_benchmark.dart';
import '../benchmark/pipeline_benchmark.dart';
import '../benchmark/ssa_driver_search_benchmark.dart';
import '../benchmark/wave_dump_benchmark.dart';

void main() {
  group('benchmark', () {
    test('pipeline', () async {
      await PipelineBenchmark().measure();
    });

    test('logic value of', () {
      LogicValueOfBenchmark().measure();
    });

    test('byte enable', () {
      ByteEnableBenchmark().measure();
    });

    test('waveform', () async {
      await WaveDumpBenchmark().measure();
    });

    group('many seq and comb', () {
      for (final connectionType in ManySeqAndCombCombConnectionType.values) {
        test(connectionType.name, () async {
          await ManySeqAndCombBenchmark(connectionType).measure();
        });
      }
    });

    test('comb guard fanout', () async {
      await CombGuardFanoutBenchmark().measure();
    });

    test('ssa driver search', () {
      SsaDriverSearchBenchmark().measure();
    });
  });
}
