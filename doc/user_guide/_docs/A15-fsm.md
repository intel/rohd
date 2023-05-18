---
title: "Finite State Machines"
permalink: /docs/fsm/
excerpt: "Finite State Machines"
last_modified_at: 2022-12-06
toc: true
---

### Finite State Machines

ROHD has a built-in syntax for handling FSMs in a simple & refactorable way.  The below example shows a 2 way Traffic light FSM.  Note that `StateMachine` consumes the `clk` and `reset` signals. Also accepts the reset state to transition to `resetState` along with the `List` of `states` of the FSM.

```dart
class TrafficTestModule extends Module {
  TrafficTestModule(Logic traffic, Logic reset) {
    traffic = addInput('traffic', traffic, width: traffic.width);
    var northLight = addOutput('northLight', width: traffic.width);
    var eastLight = addOutput('eastLight', width: traffic.width);
    var clk = SimpleClockGenerator(10).clk;
    reset = addInput('reset', reset);
    var states = [
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
    StateMachine<LightStates>(clk, reset, LightStates.northFlowing, states);
  }
}
```
