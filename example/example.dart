// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// example.dart
// A very basic example of a counter module.
//
// 2021 September 17
// Author: Max Korbel <max.korbel@intel.com>

// Though we usually avoid them, for this example,
// allow `print` messages (disable lint):
// ignore_for_file: avoid_print

// Import necessary dart pacakges for this file.
import 'dart:async';

// Import the ROHD package.
import 'package:rohd/rohd.dart';

// Define a class Counter that extends ROHD's abstract Module class.
class Counter extends Module {
  // For convenience, map interesting outputs to short variable names for
  // consumers of this module.
  Logic get val => output('val');

  // This counter supports any width, determined at run-time.
  final int width;

  Counter(Logic en, Logic reset, Logic clk,
      {this.width = 8, super.name = 'counter'}) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered
    // outputs.
    en = addInput('en', en);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    addOutput('val', width: width);

    // We can use the `flop` function to automate creation of a `Sequential`.
    val <= flop(clk, reset: reset, en: en, val + 1);
  }
}

// Let's simulate with this counter a little, generate a waveform, and take a
// look at generated SystemVerilog.
Future<void> main({bool noPrint = false}) async {
  // Define some local signals.
  final en = Logic(name: 'en');
  final reset = Logic(name: 'reset');

  // Generate a simple clock. This will run along by itself as
  // the Simulator goes.
  final clk = SimpleClockGenerator(10).clk;

  // Build a counter.
  final counter = Counter(en, reset, clk);

  // Before we can simulate or generate code with the counter, we need
  // to build it.
  await counter.build();

  // Let's see what this module looks like as SystemVerilog, so we can pass it
  // to other tools.
  final systemVerilogCode = counter.generateSynth();
  if (!noPrint) {
    print(systemVerilogCode);
  }

  // Now let's try simulating!

  // Attach a waveform dumper so we can see what happens.
  if (!noPrint) {
    WaveDumper(counter);
  }

  // Let's also print a message every time the value on the counter changes,
  // just for this example to make it easier to see before we look at waves.
  if (!noPrint) {
    counter.val.changed
        .listen((e) => print('@${Simulator.time}: Value changed: $e'));
  }

  // Start off with a disabled counter and asserting reset at the start.
  en.inject(0);
  reset.inject(1);

  // Ahead of time, register to drop reset at time 27.
  Simulator.registerAction(27, () => reset.put(0));

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(100);

  // Print a message when we're done with the simulation, too!
  Simulator.registerAction(100, () {
    if (!noPrint) {
      print('Simulation completed!');
    }
  });

  // Kick off the simulator (but don't await it)!
  if (!noPrint) {
    print('Starting simulation...');
  }
  unawaited(Simulator.run());

  // Let's wait for reset, then a few clock cycles, then enable the counter.
  await reset.nextNegedge;
  for (var i = 0; i < 3; i++) {
    await clk.nextPosedge;
  }
  en.inject(1);

  // Wait here until the simulation has completed (due to maximum time).
  await Simulator.simulationEnded;

  // We can take a look at the waves now.
  if (!noPrint) {
    print('To view waves, check out waves.vcd with a waveform viewer'
        ' (e.g. `gtkwave waves.vcd`).');
  }
}
