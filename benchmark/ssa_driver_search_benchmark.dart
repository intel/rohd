// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ssa_driver_search_benchmark.dart
// Benchmarking for searching for SSA drivers.
//
// 2023 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';

class LotsOfLogic extends Module {
  Logic get c => output('c');
  LotsOfLogic(Logic a, Logic b, int counter) {
    a = addInput('a', a);
    b = addInput('b', b);

    addOutput('c');

    if (counter == 0) {
      c <= a ^ b;
    } else {
      c <=
          List.generate(
                  counter, (index) => a ^ b ^ LotsOfLogic(a, b, counter - 1).c)
              .reduce((x, y) => x ^ y);
    }
  }
}

class LotsOfSsa extends Module {
  Logic get c => output('c');

  LotsOfSsa(Logic a, Logic b,
      {int counter = 10, int stages = 100, int signalsCount = 100}) {
    a = addInput('a', a);
    b = addInput('b', b);

    addOutput('c');

    final signals = List.generate(signalsCount,
        (index) => Logic(name: 's$index')..gets(LotsOfLogic(a, b, counter).c));

    ReadyValidPipeline(a, a, b,
        reset: b,
        signals: signals,
        stages: List.generate(
          stages,
          (index) => (p) => [
                for (final signal in signals)
                  p.get(signal) < p.get(signal) ^ LotsOfLogic(a, b, counter).c,
              ],
        ));
  }
}

class SsaDriverSearchBenchmark extends BenchmarkBase {
  SsaDriverSearchBenchmark() : super('SsaDriverSearch');

  static Module _gen() =>
      LotsOfSsa(Logic(), Logic(), counter: 5, stages: 5, signalsCount: 5);

  @override
  void run() {
    _gen();
  }
}

void main() {
  SsaDriverSearchBenchmark().report();
}
