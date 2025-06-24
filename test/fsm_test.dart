// Copyright (C) 2022-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fsm_test.dart
// Tests for fsm generators
//
// 2022 April 22
// Author: Shubham Kumar <shubham.kumar@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

enum MyStates { state1, state2, state3, state4 }

const _tmpDir = 'tmp_test';
const _simpleFSMPath = '$_tmpDir/simple_fsm.md';
const _trafficFSMPath = '$_tmpDir/traffic_light_fsm.md';

class TestModule extends Module {
  TestModule(Logic a, Logic c, Logic reset, {bool testingAsyncReset = false}) {
    a = addInput('a', a);
    c = addInput('c', c, width: c.width);
    final b = addOutput('b', width: c.width);
    final clk = testingAsyncReset ? Const(0) : SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    final states = [
      State<MyStates>(MyStates.state1, events: {
        a: MyStates.state2,
        ~a: MyStates.state3
      }, actions: [
        b < c,
      ]),
      State<MyStates>(MyStates.state2,
          conditionalType: ConditionalType.priority,
          events: {},
          actions: [
            b < 1,
          ]),
      State<MyStates>(MyStates.state3, events: {}, actions: [
        b < ~c,
      ]),
    ];

    final fsm = FiniteStateMachine<MyStates>(
        clk, reset, MyStates.state1, states,
        asyncReset: testingAsyncReset);

    if (!kIsWeb) {
      fsm.generateDiagram(outputPath: _simpleFSMPath);
    }
  }
}

class DefaultStateFsmMod extends Module {
  late final FiniteStateMachine<MyStates> _fsm;
  DefaultStateFsmMod(Logic reset) {
    reset = addInput('reset', reset);
    final clk = SimpleClockGenerator(10).clk;
    final b = addOutput('b', width: 8);

    _fsm = FiniteStateMachine<MyStates>(clk, reset, MyStates.state1, [
      State(
        MyStates.state1,
        events: {Const(0): MyStates.state2},
        actions: [b < 1],
        defaultNextState: MyStates.state3,
      ),
      State(MyStates.state2, events: {}, actions: [b < 2]),
      State(MyStates.state3,
          events: {}, actions: [b < 3], defaultNextState: MyStates.state4),
      State(MyStates.state4, events: {}, actions: [b < 4]),
    ]);
  }
}

enum LightStates { northFlowing, northSlowing, eastFlowing, eastSlowing }

enum TrafficPresence {
  noTraffic(0),
  northTraffic(1),
  eastTraffic(2),
  both(3);

  final int value;

  const TrafficPresence(this.value);

  static Logic isEastActive(Logic dir) =>
      dir.eq(TrafficPresence.eastTraffic.value) |
      dir.eq(TrafficPresence.both.value);
  static Logic isNorthActive(Logic dir) =>
      dir.eq(TrafficPresence.northTraffic.value) |
      dir.eq(TrafficPresence.both.value);
}

enum LightColor {
  green(0),
  yellow(1),
  red(2);

  final int value;

  const LightColor(this.value);
}

class TrafficTestModule extends Module {
  TrafficTestModule(Logic traffic, Logic reset) {
    traffic = addInput('traffic', traffic, width: traffic.width);
    reset = addInput('reset', reset);

    final northLight = addOutput('northLight', width: traffic.width);
    final eastLight = addOutput('eastLight', width: traffic.width);

    final clk = SimpleClockGenerator(10).clk;

    final states = <State<LightStates>>[
      State(LightStates.northFlowing, events: {
        TrafficPresence.isEastActive(traffic): LightStates.northSlowing,
      }, actions: [
        northLight < LightColor.green.value,
      ]),
      State(
        LightStates.northSlowing,
        events: {},
        defaultNextState: LightStates.eastFlowing,
        actions: [
          northLight < LightColor.yellow.value,
        ],
      ),
      State(
        LightStates.eastFlowing,
        events: {
          TrafficPresence.isNorthActive(traffic): LightStates.eastSlowing,
        },
        actions: [
          eastLight < LightColor.green.value,
        ],
      ),
      State(
        LightStates.eastSlowing,
        events: {},
        defaultNextState: LightStates.northFlowing,
        actions: [
          eastLight < LightColor.yellow.value,
        ],
      ),
    ];

    final fsm = FiniteStateMachine<LightStates>(
      clk,
      reset,
      LightStates.northFlowing,
      states,
      setupActions: [
        // by default, lights should be red
        northLight < LightColor.red.value,
        eastLight < LightColor.red.value,
      ],
    );

    if (!kIsWeb) {
      fsm.generateDiagram(outputPath: _trafficFSMPath);
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  setUpAll(() {
    if (!kIsWeb) {
      Directory(_tmpDir).createSync(recursive: true);
    }
  });

  test('zero-out receivers in default case', () async {
    final mod = TestModule(Logic(), Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains("b = 1'h0;"));
  });

  test('conditional type is used', () async {
    final mod = TestModule(Logic(), Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('priority case'));
  });

  test('label name included in generated SV', () async {
    final mod = TestModule(Logic(), Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('MyStates_state1 : begin'));
  });

  test('state value lookup is correct', () async {
    final mod = DefaultStateFsmMod(Logic());
    await mod.build();

    expect(mod._fsm.stateWidth, 2);

    expect(mod._fsm.stateIndexLookup.length, MyStates.values.length);
    expect(
        MyStates.values.every((e) => mod._fsm.stateIndexLookup.containsKey(e)),
        isTrue);
    for (var i = 0; i < MyStates.values.length; i++) {
      final stateEnum = MyStates.values[i];
      expect(mod._fsm.getStateIndex(stateEnum), i);
      expect(mod._fsm.stateIndexLookup[stateEnum], i);
    }
  });

  group('fsm validation', () {
    test('duplicate state identifiers throws exception', () {
      expect(
          () =>
              FiniteStateMachine<MyStates>(Logic(), Logic(), MyStates.state1, [
                State(MyStates.state1, events: {}, actions: []),
                State(MyStates.state2, events: {}, actions: []),
                State(MyStates.state2, events: {}, actions: []),
              ]),
          throwsA(isA<IllegalConfigurationException>()));
    });

    test('missing reset state throws exception', () {
      expect(
          () =>
              FiniteStateMachine<MyStates>(Logic(), Logic(), MyStates.state1, [
                State(MyStates.state2, events: {}, actions: []),
              ]),
          throwsA(isA<IllegalConfigurationException>()));
    });
  });

  test('state index', () {
    expect(
        FiniteStateMachine<MyStates>(Logic(), Logic(), MyStates.state1, [
          State(MyStates.state4, events: {}, actions: []),
          State(MyStates.state1, events: {}, actions: []),
          State(MyStates.state3, events: {}, actions: []),
          State(MyStates.state2, events: {}, actions: []),
        ]).getStateIndex(MyStates.state2),
        3);
  });

  group('simcompare', () {
    test('simple fsm', () async {
      final mod = TestModule(Logic(), Logic(), Logic());

      await mod.build();

      final vectors = [
        Vector({'reset': 1, 'a': 0, 'c': 0}, {}),
        Vector({'reset': 0}, {'b': 0}),
        Vector({}, {'b': 1}),
        Vector({'c': 1}, {'b': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);

      verifyMermaidStateDiagram(_simpleFSMPath);
    });

    test('simple fsm async reset', () async {
      final mod =
          TestModule(Logic(), Logic(), Logic(), testingAsyncReset: true);

      await mod.build();

      final vectors = [
        Vector({'reset': 0, 'a': 0, 'c': 0}, {}),
        Vector({'reset': 1}, {'b': 0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);

      verifyMermaidStateDiagram(_simpleFSMPath);
    });

    test('default next state fsm', () async {
      final mod = DefaultStateFsmMod(Logic());

      await mod.build();

      final vectors = [
        Vector({'reset': 1}, {}),
        Vector({'reset': 0}, {'b': 1}),
        Vector({'reset': 0}, {'b': 3}),
        Vector({'reset': 0}, {'b': 4}),
        Vector({'reset': 0}, {'b': 4}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);

      if (!kIsWeb) {
        const fsmPath = '$_tmpDir/default_next_state_fsm.md';
        mod._fsm.generateDiagram(outputPath: fsmPath);

        final mermaid = File(fsmPath).readAsStringSync();
        expect(mermaid, contains('state2'));
        expect(mermaid, contains('state3'));
        expect(mermaid, contains('state4'));
        expect(mermaid, contains('(default)'));

        verifyMermaidStateDiagram(fsmPath);
      }
    });

    test('traffic light fsm', () async {
      final mod = TrafficTestModule(Logic(width: 2), Logic());
      await mod.build();

      final vectors = [
        Vector({'reset': 1, 'traffic': 00}, {}),
        Vector({
          'reset': 0
        }, {
          'northLight': LightColor.green.value,
          'eastLight': LightColor.red.value
        }),
        Vector({}, {}),
        Vector({'traffic': TrafficPresence.eastTraffic.value}, {}),
        Vector({}, {
          'northLight': LightColor.yellow.value,
          'eastLight': LightColor.red.value
        }),
        Vector({}, {
          'northLight': LightColor.red.value,
          'eastLight': LightColor.green.value
        })
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);

      verifyMermaidStateDiagram(_trafficFSMPath);
    });
  });
}

void verifyMermaidStateDiagram(String filePath) {
  if (kIsWeb) {
    return;
  }

  // check if the diagram exist
  final file = File(filePath);
  final existDiagram = file.existsSync();
  expect(existDiagram, isTrue);

  // check if the file generated is mermaid file
  final fileContents = file.readAsStringSync();
  expect(fileContents, contains('mermaid\nstateDiagram-v2\n    '));

  File(filePath).deleteSync();
}
