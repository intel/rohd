// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// oven_fsm.dart
// A simple oven FSM implementation using ROHD.
//
// 2023 February 13
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

// ignore_for_file: avoid_print - example

// Import the ROHD package.
import 'dart:async';

import 'package:rohd/rohd.dart';

// Import the counter module implement in example.dart.
import 'example.dart';

// Enumerated type named `OvenState` with four possible states:
// `standby`, `cooking`,`paused`, and `completed`.
enum OvenState { standby, cooking, paused, completed }

enum Button { start, pause, resume }

enum LedLight { yellow, blue, red, green }

/// Assigns one bit per enum member, starting at bit zero in [values] order.
Map<T, BigInt> oneHotMapping<T extends Enum>(List<T> values) => {
      for (final (index, value) in values.indexed) value: BigInt.one << index,
    };

// Define a class OvenModule that extends ROHD's abstract Module class.
class OvenModule extends Module {
  // A private variable with type FiniteStateMachine<OvenState> `_oven`.
  //
  // Use `late` to indicate that the value will not be null
  // and will be assign in the later section.
  late FiniteStateMachine<OvenState> _oven;

  // We can expose an LED light output as a getter to retrieve it value.
  LogicEnum<LedLight> get led => output('led') as LogicEnum<LedLight>;

  // This oven module receives a `button` and a `reset` input from runtime.
  OvenModule(LogicEnum<Button> button, Logic reset, Logic clk)
      : super(name: 'OvenModule') {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered
    // outputs. `led` output also added as the output port.
    button = addTypedInput('button', button);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    final led = addTypedOutput(
        'led', LogicEnum.withMapping(oneHotMapping(LedLight.values)).clone);

    // Register local signals, `counterReset` and `en`
    // for Counter module.
    final counterReset = Logic(name: 'counter_reset');
    final en = Logic(name: 'counter_en');

    // An internal counter module that will be used to time the cooking state.
    // Receive `en`, `counterReset` and `clk` as input.
    final counter = Counter(en, counterReset, clk, name: 'counter_module');

    // A list of `OvenState` that describe the FSM. Note that
    // `OvenState` consists of identifier, events and actions. We
    // can think of `identifier` as the state name, `events` is a map of event
    // that trigger next state. `actions` is the behaviour of current state,
    // like what is the actions need to be shown separate current state with
    // other state. Represented as List of conditionals to be executed.
    final states = [
      // identifier: standby state, represent by `OvenState.standby`.
      State<OvenState>(OvenState.standby,
          // events:
          // When the button `start` is pressed during standby state,
          // OvenState will changed to `OvenState.cooking` state.
          events: {
            button.eq(Button.start): OvenState.cooking,
          },
          // actions:
          // During the standby state, `led` is change to blue; timer's
          // `counterReset` is set to 1 (Reset the timer);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LedLight.blue,
            counterReset < 1,
            en < 0,
          ]),

      // identifier: cooking state, represent by `OvenState.cooking`.
      State<OvenState>(OvenState.cooking,
          // events:
          // When the button `paused` is pressed during cooking state,
          // OvenState will changed to `OvenState.paused` state.
          //
          // When the button `counter` time is elapsed during cooking state,
          // OvenState will changed to `OvenState.completed` state.
          events: {
            button.eq(Button.pause): OvenState.paused,
            counter.val.eq(4).named('counter_time_complete'):
                OvenState.completed
          },
          // actions:
          // During the cooking state, `led` is change to yellow; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 1 (Enable value update).
          actions: [
            led < LedLight.yellow,
            counterReset < 0,
            en < 1,
          ]),

      // identifier: paused state, represent by `OvenState.paused`.
      State<OvenState>(OvenState.paused,
          // events:
          // When the button `resume` is pressed during paused state,
          // OvenState will changed to `OvenState.cooking` state.
          events: {
            button.eq(Button.resume): OvenState.cooking
          },
          // actions:
          // During the paused state, `led` is change to red; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LedLight.red,
            counterReset < 0,
            en < 0,
          ]),

      // identifier: completed state, represent by `OvenState.completed`.
      State<OvenState>(OvenState.completed,
          // events:
          // When the button `start` is pressed during completed state,
          // OvenState will changed to `OvenState.cooking` state.
          events: {
            button.eq(Button.start): OvenState.cooking
          },
          // actions:
          // During the start state, `led` is change to green; timer's
          // `counterReset` is set to 1 (Reset value);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LedLight.green,
            counterReset < 1,
            en < 0,
          ])
    ];

    // Assign the _oven FiniteStateMachine object to private variable declared.
    _oven =
        FiniteStateMachine<OvenState>(clk, reset, OvenState.standby, states);
  }

  // An oven FiniteStateMachine that represent in getter.
  FiniteStateMachine<OvenState> get ovenStateMachine => _oven;
}

/// A helper function to wait for a number of cycles.
Future<void> waitCycles(Logic clk, int numCycles) async {
  for (var i = 0; i < numCycles; i++) {
    await clk.nextPosedge;
  }
}

Future<void> main({bool noPrint = false}) async {
  // Signals `button` and `reset` that mimic user's behaviour of button pressed
  // and reset.
  //
  // LogicEnum infers a 2-bit width for the three button values.
  final button = LogicEnum(Button.values, name: 'button');
  final reset = Logic(name: 'reset');

  // A clock generator.
  final clk = SimpleClockGenerator(10).clk;

  // Build an Oven Module and passed the `button` and `reset`.
  final oven = OvenModule(button, reset, clk);

  // Generate a Mermaid FSM diagram and save as the name `oven_fsm.md`.
  // Note that the extension of the files is recommend as .md or .mmd.
  //
  // Check on https://mermaid.js.org/intro/ to view the diagram generated.
  // If you are using vscode, you can download the mermaid extension.
  if (!noPrint) {
    oven.ovenStateMachine.generateDiagram(outputPath: 'oven_fsm.md');
  }

  // Before we can simulate or generate code with the counter, we need
  // to build it.
  await oven.build();

  // Now let's try simulating!

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(300);

  // Attach a waveform dumper so we can see what happens.
  if (!noPrint) {
    oven.dumpWaves(outputPath: 'oven.vcd');
  }

  // Kick off the simulation.
  unawaited(Simulator.run());

  await clk.nextPosedge;

  // Let's start off with asserting reset to Oven.
  reset.inject(1);

  if (!noPrint) {
    // We can listen to the streams on LED light changes based on time.
    oven.led.changed.listen((_) {
      final ledVal = oven.led.valueEnum.name;

      // Print the Simulator time when the LED light changes.
      print('@t=${Simulator.time}, LED changed to: $ledVal');
    });

    button.changed.listen((_) {
      final buttonVal = button.valueEnum.name;
      print('@t=${Simulator.time}, Button changed to: $buttonVal');
    });
  }

  await waitCycles(clk, 2);

  // Drop reset
  reset.inject(0);

  // Press button start => `00`
  button.inject(Button.start);

  await waitCycles(clk, 3);

  // Press button pause => `01`
  button.inject(Button.pause);

  await waitCycles(clk, 3);

  // Press button resume => `10`
  button.inject(Button.resume);

  await waitCycles(clk, 8);

  await Simulator.endSimulation();

  // Print a message when we're done with the simulation!
  if (!noPrint) {
    print('Simulation completed!');
  }

  // We can take a look at the waves now
  if (!noPrint) {
    print('To view waves, check out waves.vcd with a'
        ' waveform viewer (e.g. `gtkwave waves.vcd`).');
  }
}
