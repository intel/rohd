/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// fsm_test.dart
/// Tests for fsm generators
///
/// 2022 April 22
/// Author: Shubham Kumar <shubham.kumar@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum MyStates { state1, state2, state3, state4 }

class TestModule extends Module {
  TestModule(Logic a, Logic c, Logic reset) {
    a = addInput('a', a);
    c = addInput('c', c, width: c.width);
    var b = addOutput('b', width: c.width);
    var clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    var states = [
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
    StateMachine<MyStates>(clk, reset, MyStates.state1, states);
  }
}

enum LightStates { northFlowing, northSlowing, eastFlowing, eastSlowing }

class Direction extends Const {
  Direction._(int value) : super(value, width: 2);
  Direction.noTraffic() : this._(bin('00'));
  Direction.northTraffic() : this._(bin('01'));
  Direction.eastTraffic() : this._(bin('10'));
  Direction.both() : this._(bin('11'));

  static Logic isEastActive(Logic dir) =>
      dir.eq(Direction.eastTraffic()) | dir.eq(Direction.both());
  static Logic isNorthActive(Logic dir) =>
      dir.eq(Direction.northTraffic()) | dir.eq(Direction.both());
}

class LightColor extends Const {
  LightColor._(int value) : super(value, width: 2);
  LightColor.green() : this._(bin('00'));
  LightColor.yellow() : this._(bin('01'));
  LightColor.red() : this._(bin('10'));
}

class TrafficTestModule extends Module {
  TrafficTestModule(Logic traffic, Logic reset) {
    traffic = addInput('traffic', traffic, width: traffic.width);
    var northLight = addOutput('northLight', width: traffic.width);
    var eastLight = addOutput('eastLight', width: traffic.width);
    var clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);

    // var eastActive = traffic[1];
    // traffic.eq(Direction.eastTraffic()) | traffic.eq(Direction.both());
    // var northActive = traffic[0];
    // traffic.eq(Direction.northTraffic()) | traffic.eq(Direction.both());

    var states = [
      State<LightStates>(LightStates.northFlowing, events: {
        ~Direction.isEastActive(traffic): LightStates.northFlowing,
        Direction.isEastActive(traffic): LightStates.northSlowing,
      }, actions: [
        northLight < LightColor.green(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.northSlowing, events: {
        Const(1): LightStates.eastFlowing,
      }, actions: [
        northLight < LightColor.yellow(),
        eastLight < LightColor.red(),
      ]),
      State<LightStates>(LightStates.eastFlowing, events: {
        ~Direction.isNorthActive(traffic): LightStates.eastFlowing,
        Direction.isNorthActive(traffic): LightStates.eastSlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.green(),
      ]),
      State<LightStates>(LightStates.eastSlowing, events: {
        Const(1): LightStates.northFlowing,
      }, actions: [
        northLight < LightColor.red(),
        eastLight < LightColor.yellow(),
      ]),
    ];
    StateMachine<LightStates>(clk, reset, LightStates.northFlowing, states);
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {
    test('simple fsm', () async {
      var pipem = TestModule(Logic(), Logic(), Logic());
      await pipem.build();

      var vectors = [
        Vector({'reset': 1, 'a': 0, 'c': 0}, {}),
        Vector({'reset': 0}, {'b': 0}),
        Vector({}, {'b': 1}),
        Vector({'c': 1}, {'b': 0}),
      ];
      await SimCompare.checkFunctionalVector(pipem, vectors);
      var simResult = SimCompare.iverilogVector(
          pipem.generateSynth(), pipem.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('traffic light fsm', () async {
      var pipem = TrafficTestModule(Logic(width: 2), Logic());
      await pipem.build();

      var vectors = [
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
      var simResult = SimCompare.iverilogVector(
          pipem.generateSynth(), pipem.runtimeType.toString(), vectors,
          signalToWidthMap: {'traffic': 2, 'northLight': 2, 'eastLight': 2});

      expect(simResult, equals(true));
    });
  });
}
