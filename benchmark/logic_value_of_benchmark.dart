/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_value_of_benchmark.dart
/// Benchmarking for concatenation of values together into one.
///
/// 2022 December 1
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class LogicValueOfBenchmark extends AsyncBenchmarkBase {
  late List<LogicValue> toOf;

  LogicValueOfBenchmark() : super('LogicValueOf');

  @override
  Future<void> setup() async {
    final rand = Random(1234);
    toOf = List.generate(
        1000,
        (index) => LogicValue.ofString(([
              '0' * rand.nextInt(10),
              '1' * rand.nextInt(10),
              'x' * rand.nextInt(10),
              'z' * rand.nextInt(10),
            ]..shuffle(rand))
                .join()));
  }

  @override
  Future<void> teardown() async {}

  @override
  Future<void> run() async {
    LogicValue.of(toOf);
  }
}

Future<void> main() async {
  await LogicValueOfBenchmark().report();
}
