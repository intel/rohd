/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// pipeline_test.dart
/// Pipelines tests!
/// 
/// 2021 October 11
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SimplePipelineModule extends Module {
  SimplePipelineModule(Logic a) : super(name: 'simple_pipeline_module') {
    var clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    var b = addOutput('b', width: a.width);

    var pipeline = Pipeline(clk,
      stages: [
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
      ]
    );
    b <= pipeline.get(a);
  }
}

class RVPipelineModule extends Module {
  RVPipelineModule(Logic a, Logic reset, Logic validIn, Logic readyForOut) : super(name: 'rv_pipeline_module') {
    var clk = SimpleClockGenerator(10).clk;
    a = addInput('a', a, width: a.width);
    validIn = addInput('validIn', validIn);
    readyForOut = addInput('readyForOut', readyForOut);
    reset = addInput('reset', reset);
    var b = addOutput('b', width: a.width);

    var pipeline = ReadyValidPipeline(clk, validIn, readyForOut,
      reset: reset,
      stages: [
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
        (p) => [
          p.get(a) < p.get(a) + 1
        ],
      ]
    );
    b <= pipeline.get(a);

    addOutput('validOut') <= pipeline.validPipeOut;
    addOutput('readyForIn') <= pipeline.readyPipeIn;
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {
    test('simple pipeline', () async {
      var pipem = SimplePipelineModule(Logic(width:8));
      await pipem.build();

      var signalToWidthMap = {
        'a':8,
        'b':8
      };

      Dumper(pipem);
      File('tmp_pipe.sv').writeAsStringSync(pipem.generateSynth());

      var vectors = [
        Vector({'a': 1}, {}),
        Vector({'a': 2}, {}),
        Vector({'a': 3}, {}),
        Vector({'a': 4}, {'b': 4}),
        Vector({'a': 4}, {'b': 5}),
        Vector({'a': 4}, {'b': 6}),
        Vector({'a': 4}, {'b': 7}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      var simResult = SimCompare.iverilogVector(pipem.generateSynth(), pipem.runtimeType.toString(), vectors, signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('rv pipeline', () async {
      var pipem = RVPipelineModule(Logic(width:8), Logic(), Logic(), Logic());
      await pipem.build();

      var signalToWidthMap = {
        'a':8,
        'b':8
      };

      Dumper(pipem);
      File('tmp_rvpipe.sv').writeAsStringSync(pipem.generateSynth());

      var vectors = [
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 1, 'a': 1, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 1, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 2, 'validIn': 1, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 3, 'validIn': 1, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 4, 'validIn': 1, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 5, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 0}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1}, {}),
        Vector({'reset': 0, 'a': 0, 'validIn': 0, 'readyForOut': 1}, {}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      var simResult = SimCompare.iverilogVector(pipem.generateSynth(), pipem.runtimeType.toString(), vectors, signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });
  });

  
}
