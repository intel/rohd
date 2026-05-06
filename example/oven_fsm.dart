// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// oven_fsm.dart
// A simple oven FSM implementation using ROHD.
//
// 2023 February 13
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

// ignore_for_file: avoid_print

// Import the ROHD package.
import 'dart:async';

import 'package:rohd/rohd.dart';

// Import module definitions (Counter, OvenModule, enums).
import 'package:rohd/src/examples/oven_fsm_modules.dart';

// Re-export module definitions so test files that import this file
// get access to OvenModule, OvenState, Button, LEDLight, etc.
export 'package:rohd/src/examples/oven_fsm_modules.dart' hide Counter;

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
  // Width of button is 2 because button is represented by a 2-bit signal.
  final button = Logic(name: 'button', width: 2);
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
    WaveDumper(oven, outputPath: 'oven.vcd');
  }

  // Kick off the simulation.
  unawaited(Simulator.run());

  await clk.nextPosedge;

  // Let's start off with asserting reset to Oven.
  reset.inject(1);

  if (!noPrint) {
    // We can listen to the streams on LED light changes based on time.
    oven.led.changed.listen((event) {
      // Get the led light enum name from LogicValue.
      final ledVal = LEDLight.values[event.newValue.toInt()].name;

      // Print the Simulator time when the LED light changes.
      print('@t=${Simulator.time}, LED changed to: $ledVal');
    });

    button.changed.listen((event) {
      final buttonVal = Button.values[event.newValue.toInt()].name;
      print('@t=${Simulator.time}, Button changed to: $buttonVal');
    });
  }

  await waitCycles(clk, 2);

  // Drop reset
  reset.inject(0);

  // Press button start => `00`
  button.inject(Button.start.value);

  await waitCycles(clk, 3);

  // Press button pause => `01`
  button.inject(Button.pause.value);

  await waitCycles(clk, 3);

  // Press button resume => `10`
  button.inject(Button.resume.value);

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
