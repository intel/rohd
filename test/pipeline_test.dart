// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pipeline_test.dart
// Tests for pipeline generators
//
// 2021 October 11
// Author: Max Korbel <max.korbel@intel.com>

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

class SimplePipelineModuleStages extends Module {
  SimplePipelineModuleStages(Logic a) : super(name: 'simple_pipeline_module') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final pipeline = Pipeline(clk, stages: [
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
    ]);
    b <= pipeline.get(a);

    for (var i = 0; i < pipeline.stageCount; i++) {
      addOutput('a$i', width: a.width) <= pipeline.get(a, i);
    }
  }
}

class SimplePipelineModuleLateAdd extends Module {
  SimplePipelineModuleLateAdd(Logic a)
      : super(name: 'simple_pipeline_module_late_add') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final pipeline = Pipeline(clk, stages: [
      (p) => [],
      (p) => [],
      (p) => [],
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
      (p) => [p.get(a) < p.get(a) + 1],
    ]);
    b <= pipeline.get(a);
  }
}

class EmptyPipe extends Module {
  Logic get b => output('b');
  EmptyPipe(Logic a) : super(name: 'pipeline_uninit') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final pipeline = Pipeline(clk, signals: [
      a,
    ], stages: [
      for (var i = 0; i < 5; i++) (p) => [],
    ]);

    b <= pipeline.get(a);
  }
}

class PipelineInitDirect extends Module {
  Logic get b => output('b');
  PipelineInitDirect(Logic a) : super(name: 'pipeline_uninit') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final c = Logic(width: a.width, name: 'c');

    final pipeline = Pipeline(clk, stages: [
      (p) => [c < a],
      (p) => [],
      (p) => [],
      (p) => [p.get(c) < p.get(c) + 1],
      (p) => [p.get(c) < p.get(c) + 1],
      (p) => [p.get(c) < p.get(c) + 1],
    ]);

    b <=
        List.generate(pipeline.stageCount, (index) => pipeline.get(c, index))
            .reduce((a, b) => a | b);
  }
}

class PipelineInitWithGet extends Module {
  Logic get b => output('b');
  PipelineInitWithGet(Logic a) : super(name: 'pipeline_uninit') {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final c = Logic(width: a.width, name: 'c');

    final pipeline = Pipeline(clk, stages: [
      (p) => [
            p.get(c) < a,
          ],
      (p) => [],
      (p) => [],
      (p) => [p.get(c) < p.get(c) + 1],
      (p) => [p.get(c) < p.get(c) + 1],
      (p) => [p.get(c) < p.get(c) + 1],
    ]);

    b <=
        List.generate(pipeline.stageCount, (index) => pipeline.get(c, index))
            .reduce((a, b) => a | b);
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

/// Based on a portion of the pipelined integer multiplier from ROHD-HCL
class PipelineWithMultiUseModule extends Module {
  PipelineWithMultiUseModule(Logic a, Logic b) {
    final clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);

    final mid = Logic(name: 'mid');
    final mid2 = Logic(name: 'mid2');

    final out = addOutput('out');

    final pipeline = Pipeline(clk, stages: [
      ...List.generate(
        3,
        (row) => (p) {
          final columnAdder = <Conditional>[];
          final maxIndexA = a.width - 1;

          for (var column = maxIndexA; column >= row; column--) {
            final tmpA =
                column == maxIndexA || row == 0 ? Const(0) : p.get(a[column]);
            final tmpB = p.get(a)[column - row] & p.get(b)[row];

            columnAdder
              ..add(p.get(mid) < tmpA + tmpB)
              ..add(p.get(mid2) < tmpA + tmpB);
          }

          return columnAdder;
        },
      ),
    ]);

    out <= pipeline.get(mid);
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

      //TODO: test that reset works!
      //TODO: test that reset value works!
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
      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('simple pipeline with intermediate gets', () async {
      final pipem = SimplePipelineModuleStages(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {'a0': 2}),
        Vector({'a': 2}, {'a0': 3, 'a1': 3}),
        Vector({'a': 3}, {'a0': 4, 'a1': 4, 'a2': 4}),
        Vector({'a': 4}, {'a0': 5, 'a1': 5, 'a2': 5, 'b': 4}),
        Vector({'a': 5}, {'a0': 6, 'a1': 6, 'a2': 6, 'a3': 5, 'b': 5}),
        Vector({'a': 6}, {'b': 6}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('getting out of range on pipeline is error', () {
      final x = Logic();
      expect(
          () => Pipeline(Logic(), signals: [
                x
              ], stages: [
                (p) => [],
                (p) => [],
              ]).get(x, 3),
          throwsRangeError);
    });

    test('getting unregisterd signal on pipeline is error', () {
      expect(
          () => Pipeline(Logic(), signals: [
                Logic()
              ], stages: [
                (p) => [],
                (p) => [],
              ]).get(Logic()),
          throwsA(isA<PortDoesNotExistException>()));
    });

    test('empty pipeline', () async {
      final pipem = EmptyPipe(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 5}, {}),
        Vector({'a': 6}, {'b': 1}),
        Vector({'a': 7}, {'b': 2}),
        Vector({'a': 8}, {'b': 3}),
        Vector({'a': 9}, {'b': 4}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('multiuse pipeline', () async {
      final pipem =
          PipelineWithMultiUseModule(Logic(width: 8), Logic(width: 8));
      await pipem.build();

      // module is gibberish, just make sure it builds and stuff
      final vectors = [
        Vector({'a': 1, 'b': 1}, {}),
        Vector({'a': 2, 'b': 1}, {}),
        Vector({'a': 2, 'b': 2}, {}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('simple pipeline late add', () async {
      final pipem = SimplePipelineModuleLateAdd(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {'b': 4}),
        Vector({'a': 4}, {'b': 5}),
        Vector({'a': 4}, {'b': 6}),
        Vector({'a': 4}, {'b': 7}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('pipeline initialized via get', () async {
      final pipem = PipelineInitWithGet(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);

      expect(pipem.b.value.isValid, isTrue);

      SimCompare.checkIverilogVector(pipem, vectors);
    });

    test('pipeline initialized directly instead of via get', () async {
      final pipem = PipelineInitDirect(Logic(width: 8));
      await pipem.build();

      final vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
        Vector({'a': 4}, {}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);

      expect(pipem.b.value.isValid, isTrue);

      SimCompare.checkIverilogVector(pipem, vectors);
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
      SimCompare.checkIverilogVector(pipem, vectors);
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
      SimCompare.checkIverilogVector(pipem, vectors);
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
      SimCompare.checkIverilogVector(pipem, vectors);
    });
  });
}
