---
title: "Finite State Machines"
permalink: /docs/fsm/
excerpt: "Finite State Machines"
last_modified_at: 2023-09-19
toc: true
---

ROHD has a built-in syntax for handling Finite State Machines (FSM) in a simple & refactorable way. To illustrate, the below example shows a two-way traffic light controller FSM with some basic rules:

- The usual traffic light colors: green means go, yellow means slow, red means stop
- Only either north/south or east/west traffic is allowed at a given time
- Always transition through a yellow light before going to red
- Trigger a transition between north/south and east/west flowing when there is traffic waiting at a red light

With the ROHD [`FiniteStateMachine`](https://intel.github.io/rohd/rohd/FiniteStateMachine-class.html), we can just describe the state machine architecturally and let ROHD take care of the low-level implementation details.

First, let's define our states ("flowing" means green for them, red for the other; "slowing" means yellow for them, red for the other). For simplicity, we just refer to "north" and "east" instead of "north/south" and "east/west".

```dart
enum LightStates { northFlowing, northSlowing, eastFlowing, eastSlowing }
```

Now let's make some representation for different cases of traffic wishing to go through the intersection. Let's also add some helper functions to compute whether there's pending traffic in each direction, since the "both" case is true for either one.

```dart
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
```

Now, let's define the encoding of outputs (the color of the light).

```dart
enum LightColor {
  green(0),
  yellow(1),
  red(2);

  final int value;

  const LightColor(this.value);
}
```

Now we can go ahead and describe the set of states for our state machine. Note that for each state, we describe a few things:

- Identify the name of the state (one of `LightStates`)
- Define `events` that cause a transition to another state. If none of the events occur, it will stay in the same state by default, but that's configurable via the `defaultNextState`. In this case, if there's traffic waiting at a red light, we start transitioning. If we're yellow, go to red state next.
- Define `actions` that should occur when in that state.  In this case, we set the light colors based on the state.

```dart
final states = <State<LightStates>>[
  State(LightStates.northFlowing, events: {
    TrafficPresence.isEastActive(traffic): LightStates.northSlowing,
  }, actions: [
    northLight < LightColor.green.value,
    eastLight < LightColor.red.value,
  ]),
  State(
    LightStates.northSlowing,
    events: {},
    defaultNextState: LightStates.eastFlowing,
    actions: [
      northLight < LightColor.yellow.value,
      eastLight < LightColor.red.value,
    ],
  ),
  State(
    LightStates.eastFlowing,
    events: {
      TrafficPresence.isNorthActive(traffic): LightStates.eastSlowing,
    },
    actions: [
      northLight < LightColor.red.value,
      eastLight < LightColor.green.value,
    ],
  ),
  State(
    LightStates.eastSlowing,
    events: {},
    defaultNextState: LightStates.northFlowing,
    actions: [
      northLight < LightColor.red.value,
      eastLight < LightColor.yellow.value,
    ],
  ),
];
```

Now, constructing the state machine itself is easy.  LEt's start at the north/south flowing state.

```dart
FiniteStateMachine<LightStates>(
  clk,
  reset,
  LightStates.northFlowing,
  states,
);
```

This state machine is now functional and synthesizable into SystemVerilog!

You can even generate a mermaid diagram for the state machine using the [`generateDiagram`](https://intel.github.io/rohd/rohd/FiniteStateMachine/generateDiagram.html) API.

You can see a full executable example of this state machine in [`test/fsm_test.dart`](https://github.com/intel/rohd/blob/main/test/fsm_test.dart) in the ROHD repository.
