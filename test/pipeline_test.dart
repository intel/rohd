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
  });
}