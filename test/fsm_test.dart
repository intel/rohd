/// Copyright (C) 2022-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// fsm_test.dart
/// Tests for fsm generators
///
/// 2022 April 22
/// Author: Shubham Kumar <shubham.kumar@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum MyStates { state1, state2, state3, state4 }

class TestModule extends Module {
  TestModule(Logic a, Logic c, Logic reset) {
    a = addInput('a', a);
    c = addInput('c', c, width: c.width);
    final b = addOutput('b', width: c.width);
    final clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    final states = [
      State<MyStates>(MyStates.state1, events: {
        a: MyStates.state2,
        ~a: MyStates.state3
      }, actions: [
        b < c,
      ]),
      State<MyStates>(MyStates.state2, events: {}, actions: []),
      State<MyStates>(MyStates.state3, events: {}, actions: [
        b < ~c,
      ]),
    ];

    StateMachine<MyStates>(clk, reset, MyStates.state1, states)
        .generateDiagram(outputPath: 'tmp_test/simple_fsm.md');
  }
}

enum LightStates { northFlowing, northSlowing, eastFlowing, eastSlowing }

class Direction extends Const {
  Direction._(int super.value) : super(width: 2);
  Direction.noTraffic() : this._(bin('00'));
  Direction.northTraffic() : this._(bin('01'));
  Direction.eastTraffic() : this._(bin('10'));
  Direction.both() : this._(bin('11'));
}

class LightColor extends Const {
  LightColor._(int super.value) : super(width: 2);
  LightColor.green() : this._(bin('00'));
  LightColor.yellow() : this._(bin('01'));
  LightColor.red() : this._(bin('10'));
}

class TrafficTestModule extends Module {
  TrafficTestModule(Logic traffic, Logic reset) {
    traffic = addInput('traffic', traffic, width: traffic.width);
    final northLight = addOutput('northLight', width: traffic.width);
    final eastLight = addOutput('eastLight', width: traffic.width);
    final clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    final states = [
      State<LightStates>(LightStates.northFlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.northSlowing,
        traffic.eq(Direction.both()): LightStates.northSlowing,
      }, actions: [
        northLight < LightColor.green(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.northSlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.both()): LightStates.eastFlowing,
      }, actions: [
        northLight < LightColor.yellow(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.eastFlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.eastSlowing,
        traffic.eq(Direction.northTraffic()): LightStates.eastSlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.eastFlowing,
        traffic.eq(Direction.both()): LightStates.eastSlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.green(),
      ]),
      State<LightStates>(LightStates.eastSlowing, events: {
        traffic.eq(Direction.noTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.northTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.eastTraffic()): LightStates.northFlowing,
        traffic.eq(Direction.both()): LightStates.northFlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.yellow(),
      ]),
    ];

    StateMachine<LightStates>(clk, reset, LightStates.northFlowing, states)
        .generateDiagram(outputPath: 'tmp_test/traffic_light_fsm.md');
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  const simpleFSMPath = 'tmp_test/simple_fsm.md';
  const trafficFSMPath = 'tmp_test/traffic_light_fsm.md';

  group('simcompare', () {
    test('simple fsm', () async {
      final pipem = TestModule(Logic(), Logic(), Logic());

      await pipem.build();

      final vectors = [
        Vector({'reset': 1, 'a': 0, 'c': 0}, {}),
        Vector({'reset': 0}, {'b': 0}),
        Vector({}, {'b': 1}),
        Vector({'c': 1}, {'b': 0}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);

      expect(simResult, equals(true));

      verifyMermaidStateDiagram(simpleFSMPath);
    });

    test('traffic light fsm', () async {
      final pipem = TrafficTestModule(Logic(width: 2), Logic());
      await pipem.build();

      final vectors = [
        Vector({'reset': 1, 'traffic': 00}, {}),
        Vector({
          'reset': 0
        }, {
          'northLight': LightColor.green().value,
          'eastLight': LightColor.red().value
        }),
        Vector({}, {}),
        Vector({'traffic': Direction.eastTraffic().value}, {}),
        Vector({}, {
          'northLight': LightColor.yellow().value,
          'eastLight': LightColor.red().value
        }),
        Vector({}, {
          'northLight': LightColor.red().value,
          'eastLight': LightColor.green().value
        })
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      final simResult = SimCompare.iverilogVector(pipem, vectors);

      expect(simResult, equals(true));
      verifyMermaidStateDiagram(trafficFSMPath);
    });
  });
}

void verifyMermaidStateDiagram(String filePath) {
  // check if the diagram exist
  final file = File(filePath);
  final existDiagram = file.existsSync();
  expect(existDiagram, isTrue);

  // check if the file generated is mermaid file
  final fileContents = file.readAsStringSync();
  expect(fileContents, contains('mermaid\nstateDiagram-v2\n    '));

  File(filePath).deleteSync();
}
