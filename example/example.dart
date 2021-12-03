/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// example.dart
/// A very basic example of a counter module.
///
/// 2021 September 17
/// Author: Max Korbel <max.korbel@intel.com>
///

// Import the ROHD package
import 'package:rohd/rohd.dart';

// Define a class Counter that extends ROHD's abstract Module class
class Counter extends Module {
  // For convenience, map interesting outputs to short variable names for consumers of this module
  Logic get val => output('val');

  // This counter supports any width, determined at run-time
  final int width;
  Counter(Logic en, Logic reset, Logic clk,
      {this.width = 8, String name = 'counter'})
      : super(name: name) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered outputs.
    en = addInput('en', en);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);

    var val = addOutput('val', width: width);

    // A local signal named 'nextVal'
    var nextVal = Logic(name: 'nextVal', width: width);

    // Assignment statement of nextVal to be val+1 (<= is the assignment operator)
    nextVal <= val + 1;

    // `FF` is like SystemVerilog's always_ff, in this case trigger on the positive edge of clk
    FF(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog always blocks
      If(reset, then: [
        // the '<' operator is a conditional assignment
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}

// Let's simulate with this counter a little, generate a waveform, and take a look at generated SystemVerilog.
Future<void> main({bool noPrint = false}) async {
  // Define some local signals.
  var en = Logic(name: 'en'), reset = Logic(name: 'reset');

  // Generate a simple clock.  This will run along by itself as the Simulator goes.
  var clk = SimpleClockGenerator(10).clk;

  // Build a counter.
  var counter = Counter(en, reset, clk);

  // Before we can simulate or generate code with the counter, we need to build it.
  await counter.build();

  // Let's see what this module looks like as SystemVerilog, so we can pass it to other tools.
  var systemVerilogCode = counter.generateSynth();
  if (!noPrint) print(systemVerilogCode);

  // Now let's try simulating!

  // Let's start off with a disabled counter and asserting reset.
  en.inject(0);
  reset.inject(1);

  // Attach a waveform dumper so we can see what happens.
  WaveDumper(counter);

  // Drop reset at time 25.
  Simulator.registerAction(25, () => reset.put(0));

  // Raise enable at time 45.
  Simulator.registerAction(45, () => en.put(1));

  // Print a message when we're done with the simulation!
  Simulator.registerAction(100, () {
    if (!noPrint) print('Simulation completed!');
  });

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(100);

  // Kick off the simulation.
  await Simulator.run();

  // We can take a look at the waves now.
  if (!noPrint) {
    print(
        'To view waves, check out waves.vcd with a waveform viewer (e.g. `gtkwave waves.vcd`).');
  }
}
