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

class ByteEnableBenchmark extends AsyncBenchmarkBase {
  late Logic result;
  late Logic select;
  late Logic original;

  static const int numBytes = 128;

  final List<LogicValue> vectors = List.generate(
      numBytes,
      (index) => LogicValue.ofString(
          (index.toRadixString(2) * numBytes).substring(0, numBytes)));

  ByteEnableBenchmark() : super('ByteEnable');

  @override
  Future<void> setup() async {
    select = Logic(name: 'select', width: numBytes);
    original = Logic(name: 'original', width: numBytes * 8);
    original.put(LogicValue.ofString('0x1z10xz' * numBytes));
    select.put(0);
    result = List.generate(
        numBytes,
        (index) => mux(
              select[index],
              original.getRange(index * 8, (index + 1) * 8),
              Const(0, width: 8),
            )).swizzle();
  }

  @override
  Future<void> teardown() async {}

  @override
  Future<void> run() async {
    vectors.forEach(select.put);
  }
}

Future<void> main() async {
  await ByteEnableBenchmark().report();
}
