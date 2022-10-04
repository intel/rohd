/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// increment_value.dart
/// Increment a value by 1
///
/// 2021 September 17
/// Author: Rahul Gautham Putcha <rahul.gautham.putcha@intel.com>
///

// Import the ROHD package

import 'package:rohd/rohd.dart';

class Rough extends Module {
  // For convenience, map interesting outputs to short variable names for consumers of this module
  Logic get nextVal => output('nextVal');
  final int width;
  Rough(Logic val, {this.width = 8, String name = 'rough'})
      : super(name: name) {
    val = addInput('val', val, width: width);
    var nextVal = addOutput('nextVal', width: width);
    nextVal <= val + 0x1; // Increment a value by 1
  }
}

// Let's simulate with this counter a little, generate a waveform, and take a look at generated SystemVerilog.
Future<void> main({bool noPrint = false}) async {
  // Define some local signals.
  var en = Logic(name: 'en', width: 8);

  // Build a counter.
  var counter = Rough(en);

  // Before we can simulate or generate code with the counter, we need to build it.
  await counter.build();

  // Let's see what this module looks like as SystemVerilog, so we can pass it to other tools.
  var systemVerilogCode = counter.generateSynth();
  if (!noPrint) print(systemVerilogCode);

  // Now let's try simulating!

  // Let's start off with a disabled counter and asserting reset.
  en.inject(0);

  // Attach a waveform dumper so we can see what happens.
  if (!noPrint) WaveDumper(counter);

  // Raise enable at time 45.
  Simulator.registerAction(
      45, () => en.put(1)); // substituting value at time 45

  // Print a message when we're done with the simulation!
  Simulator.registerAction(100, () {
    // print (sim...) at time 100
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
