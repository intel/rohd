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

// Import the ROHD package.
import 'package:rohd/rohd.dart';

// Import the counter module implement in example.dart.
import './example.dart';

// Enumerated type named `OvenState` with four possible states:
// `standby`, `cooking`,`paused`, and `completed`.
enum OvenState { standby, cooking, paused, completed }

// One-hot encoded `Button` using dart enhanced enums.
// Represent start, pause, and resume as integer value 0, 1,
// and 2 respectively.
enum Button {
  start(value: 0),
  pause(value: 1),
  resume(value: 2);

  const Button({required this.value});

  final int value;
}

// One-hot encoded `LEDLight` using dart enhanced enums.
// Represent yellow, blue, red, and green  as integer value 0, 1,
// 2, and 3 respectively.
enum LEDLight {
  yellow(value: 0),
  blue(value: 1),
  red(value: 2),
  green(value: 3);

  const LEDLight({required this.value});

  final int value;
}

// Define a class OvenModule that extends ROHD's abstract Module class.
class OvenModule extends Module {
  // A private variable with type StateMachine<OvenState> `_oven`.
  //
  // Use `late` to indicate that the value will not be null
  // and will be assign in the later section.
  late StateMachine<OvenState> _oven;

  // We can expose an LED light output as a getter to retrieve it value.
  Logic get led => output('led');

  // This oven module receives a `button` and a `reset` input from runtime.
  OvenModule(Logic button, Logic reset) : super(name: 'OvenModule') {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered
    // outputs. `led` output also added as the output port.
    button = addInput('button', button, width: button.width);
    reset = addInput('reset', reset);
    final led = addOutput('led', width: button.width);

    // An internal clock generator.
    final clk = SimpleClockGenerator(10).clk;

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
            Logic(name: 'button_start')
                  ..gets(button
                      .eq(Const(Button.start.value, width: button.width))):
                OvenState.cooking,
          },
          // actions:
          // During the standby state, `led` is change to blue; timer's
          // `counterReset` is set to 1 (Reset the timer);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LEDLight.blue.value,
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
            Logic(name: 'button_pause')
                  ..gets(button
                      .eq(Const(Button.pause.value, width: button.width))):
                OvenState.paused,
            Logic(name: 'counter_time_complete')..gets(counter.val.eq(4)):
                OvenState.completed
          },
          // actions:
          // During the cooking state, `led` is change to yellow; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 1 (Enable value update).
          actions: [
            led < LEDLight.yellow.value,
            counterReset < 0,
            en < 1,
          ]),

      // identifier: paused state, represent by `OvenState.paused`.
      State<OvenState>(OvenState.paused,
          // events:
          // When the button `resume` is pressed during paused state,
          // OvenState will changed to `OvenState.cooking` state.
          events: {
            Logic(name: 'button_resume')
                  ..gets(button
                      .eq(Const(Button.resume.value, width: button.width))):
                OvenState.cooking
          },
          // actions:
          // During the paused state, `led` is change to red; timer's
          // `counterReset` is set to 0 (Do not reset);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LEDLight.red.value,
            counterReset < 0,
            en < 0,
          ]),

      // identifier: completed state, represent by `OvenState.completed`.
      State<OvenState>(OvenState.completed,
          // events:
          // When the button `start` is pressed during completed state,
          // OvenState will changed to `OvenState.cooking` state.
          events: {
            Logic(name: 'button_start')
                  ..gets(button
                      .eq(Const(Button.start.value, width: button.width))):
                OvenState.cooking
          },
          // actions:
          // During the start state, `led` is change to green; timer's
          // `counterReset` is set to 1 (Reset value);
          // timer's `en` is set to 0 (Disable value update).
          actions: [
            led < LEDLight.green.value,
            counterReset < 1,
            en < 0,
          ])
    ];

    // Assign the _oven StateMachine object to private variable declared.
    _oven = StateMachine<OvenState>(clk, reset, OvenState.standby, states);
  }

  // An ovenStateMachine that represent in getter.
  StateMachine<OvenState> get ovenStateMachine => _oven;
}

Future<void> main({bool noPrint = false}) async {
  // Signals `button` and `reset` that mimic user's behaviour of button pressed
  // and reset.
  //
  // Width of button is 2 because button is represent by 2-bits signal.
  final button = Logic(name: 'button', width: 2);
  final reset = Logic(name: 'reset');

  // Build an Oven Module and passed the `button` and `reset`.
  final oven = OvenModule(button, reset);

  // Generate a Mermaid FSM diagram and save as the name `oven_fsm.md`.
  // Note that the extension of the files is recommend as .md or .mmd.
  //
  // Check on https://mermaid.js.org/intro/ to view the diagram generated.
  // If you are using vscode, you can download the mermaid extension.
  oven.ovenStateMachine.generateDiagram(outputPath: 'oven_fsm.md');

  // Before we can simulate or generate code with the counter, we need
  // to build it.
  await oven.build();

  // Now let's try simulating!

  // Let's start off with asserting reset to Oven.
  reset.inject(1);

  // Attach a waveform dumper so we can see what happens.
  if (!noPrint) {
    WaveDumper(oven, outputPath: 'oven.vcd');
  }

  if (!noPrint) {
    // We can listen to the streams on LED light changes based on time.
    oven.led.changed.listen((event) {
      // Get the led light enum name from LogicValue.
      final ledVal = LEDLight.values[event.newValue.toInt()].name;

      // Print the Simulator time when the LED light changes.
      print('@t=${Simulator.time}, LED changed to: $ledVal');
    });
  }

  // Drop reset at time 25.
  Simulator.registerAction(25, () => reset.put(0));

  // Press button start => `00` at time 25.
  Simulator.registerAction(25, () {
    button.put(Button.start.value);
  });

  // Press button pause => `01` at time 50.
  Simulator.registerAction(50, () {
    button.put(Button.pause.value);
  });

  // Press button resume => `10` at time 70.
  Simulator.registerAction(70, () {
    button.put(Button.resume.value);
  });

  // Print a message when we're done with the simulation!
  Simulator.registerAction(120, () {
    if (!noPrint) {
      print('Simulation completed!');
    }
  });

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(120);

  // Kick off the simulation.
  await Simulator.run();

  // We can take a look at the waves now
  if (!noPrint) {
    print('To view waves, check out waves.vcd with a'
        ' waveform viewer (e.g. `gtkwave waves.vcd`).');
  }
}
