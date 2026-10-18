// Copyright (C) 2022-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// benchmark_test.dart
// Tests that run benchmarks to make sure they don't break.
//
// 2022 September 28
// Author: Max Korbel <max.korbel@intel.com>

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

import '../benchmark/byte_enable_benchmark.dart';
import '../benchmark/comb_guard_fanout_benchmark.dart';
import '../benchmark/logic_value_of_benchmark.dart';
import '../benchmark/many_seq_and_comb_benchmark.dart';
import '../benchmark/many_submodules_benchmark.dart';
import '../benchmark/pipeline_benchmark.dart';
import '../benchmark/ssa_driver_search_benchmark.dart';
import '../benchmark/wave_dump_benchmark.dart';

/// Runs one pass of each phase. The timing loop in `measure()` runs for
/// seconds per benchmark, which is unnecessary for checking they still work.
void smokeRun(BenchmarkBase benchmark) {
  benchmark
    ..setup()
    ..run()
    ..teardown();
}

Future<void> smokeRunAsync(AsyncBenchmarkBase benchmark) async {
  await benchmark.setup();
  await benchmark.run();
  await benchmark.teardown();
}

void main() {
  group('benchmark', tags: 'benchmark', () {
    test('pipeline', () async {
      await smokeRunAsync(PipelineBenchmark());
    });

    test('logic value of', () {
      smokeRun(LogicValueOfBenchmark());
    });

    test('byte enable', () {
      smokeRun(ByteEnableBenchmark());
    });

    if (!kIsWeb) {
      test('waveform', () async {
        await smokeRunAsync(WaveDumpBenchmark());
      });
    }

    group('many seq and comb', () {
      for (final connectionType in ManySeqAndCombCombConnectionType.values) {
        test(connectionType.name, () async {
          await smokeRunAsync(ManySeqAndCombBenchmark(connectionType));
        });
      }
    });

    test('comb guard fanout', () async {
      await smokeRunAsync(CombGuardFanoutBenchmark());
    });

    test('ssa driver search', () {
      smokeRun(SsaDriverSearchBenchmark());
    });

    test('many submodule', () async {
      await smokeRunAsync(ManySubmodulesBenchmark());
    });
  });
}
