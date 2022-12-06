/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// byte_enable_benchmark.dart
/// Benchmarking for simple byte enable hardware
///
/// 2022 December 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class ByteEnableBenchmark extends BenchmarkBase {
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
  void setup() {
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
  void teardown() {}

  @override
  void run() {
    vectors.forEach(select.put);
  }
}

void main() {
  ByteEnableBenchmark().report();
}
