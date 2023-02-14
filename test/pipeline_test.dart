/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// pipeline_test.dart
/// Tests for pipeline generators
///
/// 2021 October 11
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SimplePipelineModule extends Module {
  SimplePipelineModule(Logic a) : super(name: 'simple_pipeline_module') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final pipeline = Pipeline(clk, stages: [
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
    ]);
    b <= pipeline.get(a);
  }
}

class RVPipelineModule extends Module {
  RVPipelineModule(Logic a, Logic reset, Logic validIn, Logic readyForOut)
      : super(name: 'rv_pipeline_module') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    validIn = addInput('validIn', validIn);
    readyForOut = addInput('readyForOut', readyForOut);
    reset = addInput('reset', reset);
    final b = addOutput('b', width: a.width);

    final pipeline =
        ReadyValidPipeline(clk, validIn, readyForOut, reset: reset, stages: [
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
    ]);
    b <= pipeline.get(a);

    addOutput('validOut') <= pipeline.validPipeOut;
    addOutput('readyForIn') <= pipeline.readyPipeIn;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('simple pipeline', () async {
      final pipem = SimplePipelineModule(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {'b': 4}),
        Vector({'a': 4}, {'b': 5}),
        Vector({'a': 4}, {'b': 6}),
        Vector({'a': 4}, {'b': 7}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);
      expect(simResult, equals(true));
    });

    test('rv pipeline simple', () async {
      final pipem =
          RVPipelineModule(Logic(width: 8), Logic(), Logic(), Logic());
      await pipem.build();

      final vectors = [
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 1, 'validIn': 1, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 2, 'validIn': 1, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 3, 'validIn': 1, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 4, 'validIn': 1, 'readyForOut': 1},
            {'validOut': 1, 'b': 4}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 5}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 6}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 7}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);
      expect(simResult, equals(true));
    });

    test('rv pipeline notready', () async {
      final pipem =
          RVPipelineModule(Logic(width: 8), Logic(), Logic(), Logic());
      await pipem.build();

      final vectors = [
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0x10, 'validIn': 1, 'readyForOut': 0},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1, 'b': 0x13}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0x20, 'validIn': 1, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0x30, 'validIn': 1, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1, 'b': 0x13}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x13}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x23}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x33}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);
      expect(simResult, equals(true));
    });

    test('rv pipeline multi', () async {
      final pipem =
          RVPipelineModule(Logic(width: 8), Logic(), Logic(), Logic());
      await pipem.build();

      final vectors = [
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0x10, 'validIn': 1, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0x20, 'validIn': 1, 'readyForOut': 0},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0x30, 'validIn': 1, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1, 'b': 0x13}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x13}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0},
            {'validOut': 1, 'b': 0x23}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x23}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 1, 'b': 0x33}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1},
            {'validOut': 0}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);
      expect(simResult, equals(true));
    });
  });
}
