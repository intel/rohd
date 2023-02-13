/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// oven_fsm.dart
/// A simple oven FSM implementation using ROHD.
///
/// 2023 February 13
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

// Import the ROHD package
import 'package:rohd/rohd.dart';

// Import the counter module implement in example.dart
import './example.dart';

// Enumerated type named `OvenStates` with four possible states:
// `standby`, `cooking`,`paused`, and `completed`.
enum OvenStates { standby, cooking, paused, completed }

// One-hot encoded `Button` that extends from Const() value.
// Represent start, pause, and resume as constant value `00`, `01`,
// and `10` respectively.
class Button extends Const {
  Button._(int super.value) : super(width: 2);
  Button.start() : this._(bin('00'));
  Button.pause() : this._(bin('01'));
  Button.resume() : this._(bin('10'));
}

// One-hot encoded `LEDLight` that extends from Const() value.
// Represent yellow, blue, red and green LED as constant value `00`, `01`,
// `10`, and `11` respectively.
class LEDLight extends Const {
  LEDLight._(int super.value) : super(width: 2);
  LEDLight.yellow() : this._(bin('00'));
  LEDLight.blue() : this._(bin('01'));
  LEDLight.red() : this._(bin('10'));
  LEDLight.green() : this._(bin('11'));
}

// Define a class OvenModule that extends ROHD's abstract Module class
class OvenModule extends Module {
  // A public variable with type StateMachine<OvenStates> `oven`.
  // We want to return this variable to the main module for flexbility.
  // Use `late` to indicate that the value will not be null
  // and will be assign in the later section.
  late StateMachine<OvenStates> oven;

  // This oven module receives a `button` and a `reset` input from runtime.
  OvenModule(Logic button, Logic reset) : super(name: 'OvenModule') {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered
    // outputs. `led` output also added as the output port.
    button = addInput('button', button, width: button.width);
    reset = addInput('reset', reset);
    final led = addOutput('led', width: button.width);

    // An internal clock generator
    final clk = SimpleClockGenerator(10).clk;

    // Register inputs and outputs, `counterReset` and `en` for internal signals to be used in
    // Counter module.
    final counterReset = Logic(name: 'counter_reset');
    final en = Logic(name: 'counter_en');

    // An internal counter module that will be used to time the cooking state.
    // Receive `en`, `counterReset` and `clk` as input.
    final counter = Counter(en, counterReset, clk, name: 'counter_module');

    // A list of `OvenStates` that describe the FSM. Note that
    // `OvenStates` consists of identifier, events and actions. We
    // can think of `identifier` as the state name, `events` is a map of event
    // that trigger next state. `actions` is the behaviour of current state,
    // like what is the actions need to be shown separate current state with
    // other state. Represented as List of conditionals to be executed.
    final states = [
      // [identifier]: standby state, represent by `OvenStates.standby`.
      State<OvenStates>(OvenStates.standby,
          // [events]: When the button `start` is pressed during standby state,
          // OvenState will changed to `OvenStates.cooking` state.
          events: {
            Logic(name: 'button_start')..gets(button.eq(Button.start())):
                OvenStates.cooking,
          }, actions: [
        // [actions]: During the standby state, `led` is change to blue; timer's
        // `counterReset` is set to 1 (Reset the timer);
        // timer's `en` is set to 0 (Disable value update).
        led < LEDLight.blue().value,
        counterReset < 1,
        en < 0,
      ]),

      // [identifier]: cooking state, represent by `OvenStates.cooking`.
      State<OvenStates>(OvenStates.cooking,
          // [events]:
          // When the button `paused` is pressed during cooking state,
          // OvenState will changed to `OvenStates.paused` state.
          //
          // When the button `counter` time is elapsed during cooking state,
          // OvenState will changed to `OvenStates.completed` state.
          events: {
            Logic(name: 'button_pause')..gets(button.eq(Button.pause())):
                OvenStates.paused,
            Logic(name: 'counter_time_complete')..gets(counter.val.eq(4)):
                OvenStates.completed
          },
          // [actions]:
          // During the cooking state, `led` is change to yellow; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 1 (Enable value update).
          actions: [
            led < LEDLight.yellow().value,
            counterReset < 0,
            en < 1,
          ]),

      // [identifier]: paused state, represent by `OvenStates.paused`.
      State<OvenStates>(OvenStates.paused,
          // [events]:
          // When the button `resume` is pressed during paused state,
          // OvenState will changed to `OvenStates.cooking` state.
          events: {
            Logic(name: 'button_resume')..gets(button.eq(Button.resume())):
                OvenStates.cooking
          },
          // [actions]:
          // During the paused state, `led` is change to red; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LEDLight.red().value,
            counterReset < 0,
            en < 0,
          ]),

      // [identifier]: completed state, represent by `OvenStates.completed`.
      State<OvenStates>(OvenStates.completed,
          // [events]:
          // When the button `start` is pressed during completed state,
          // OvenState will changed to `OvenStates.cooking` state.
          events: {
            Logic(name: 'button_start')..gets(button.eq(Button.start())):
                OvenStates.cooking
          },
          // [actions]:
          // During the start state, `led` is change to green; timer's
          // `counterReset` is set to 1 (Reset value);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LEDLight.green().value,
            counterReset < 1,
            en < 0,
          ])
    ];

    // Assign the oven StateMachine object to public variable declared.
    oven = StateMachine<OvenStates>(clk, reset, OvenStates.standby, states);
  }

  // An ovenStateMachine that represent in getter.
  StateMachine<OvenStates> get ovenStateMachine => oven;
}

void main() async {
  // Signals `button` and `reset` that mimic user's behaviour of button pressed and reset.
  // Width of button is 2 because button is represent by 2-bits signal.
  final button = Logic(name: 'button', width: 2);
  final reset = Logic(name: 'reset');

  // Build an Oven Module and passed the `button` and `reset`.
  final oven = OvenModule(button, reset);

  // Generate a FSM diagram and save as the name `oven_fsm.md`. Note that
  // the extension of the files is recommend as .md or .mmd.
  oven.ovenStateMachine.generateDiagram(outputPath: 'oven_fsm.md');

  // Before we can simulate or generate code with the counter, we need
  // to build it.
  await oven.build();

  // Now let's try simulating!

  // Let's start off with asserting reset to Oven.
  reset.inject(1);

  // Attach a waveform dumper so we can see what happens.
  WaveDumper(oven, outputPath: 'example/oven.vcd');

  // Drop reset at time 25.
  Simulator.registerAction(25, () => reset.put(0));

  // Press button `00` => start at time 25.
  Simulator.registerAction(25, () {
    button.put(bin('00'));
  });

  // Press button `01` => pause at time 50.
  Simulator.registerAction(50, () {
    button.put(bin('01'));
  });

  // Press button `10` => resume at time 70.
  Simulator.registerAction(70, () {
    button.put(bin('10'));
  });

  // Print a message when we're done with the simulation!
  Simulator.registerAction(120, () {
    // ignore: avoid_print
    print('Simulation End');
  });

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(120);

  // Kick off the simulation.
  await Simulator.run();
}
