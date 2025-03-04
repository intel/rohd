// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mux.dart
// A very basic example of a MUX module
// to show case the selectIndex and selectFrom
//
// 2025 March 04
// Author: Ramli, Nurul Izziany <nurul.izziany.ramli@intel.com>

// Though we usually avoid them, for this example,
// allow `print` messages (disable lint):
// ignore_for_file: avoid_print

// Import necessary dart pacakges for this file.
import 'dart:async';

// Import the ROHD package.
import 'package:rohd/rohd.dart';

class MuxExample extends Module {
  Logic get select => input('select');
  Logic get out => output('out');

  MuxExample(Logic select, Logic in0, Logic in1, Logic in2, Logic out)
      : super(name: 'mux_example') {
    select = addInput(select.name, select, width: select.width);
    in0 = addInput(in0.name, in0, width: in0.width);
    in1 = addInput(in1.name, in1, width: in1.width);
    in2 = addInput(in2.name, in2, width: in2.width);
    out = addOutput('out', width: out.width);

    final defaultValue = Const(0, width: out.width);
    final arrayA = <Logic>[in0, in1, in2];

    // Use selectIndex or selectFrom to select a value from an array
    out <= arrayA.selectIndex(select, defaultValue: defaultValue);
    // out <= select.selectFrom(arrayA, defaultValue: defaultValue);
  }
}

Future<void> main({bool noPrint = false}) async {
  final select = Logic(name: 'select', width: 2);
  final in0 = Logic(name: 'in0', width: 3);
  final in1 = Logic(name: 'in1', width: 3);
  final in2 = Logic(name: 'in2', width: 3);
  final out = Logic(name: 'out', width: 3);

  final mux = MuxExample(select, in0, in1, in2, out);

  await mux.build();

  final systemVerilogCode = mux.generateSynth();
  if (!noPrint) {
    print(systemVerilogCode);
  }

  // Simulate the module
  if (!noPrint) {
    WaveDumper(mux);
  }

  // Set the input values
  in0.inject(1);
  in1.inject(2);
  in2.inject(3);

  // Print a message when the select and the out value changes
  if (!noPrint) {
    mux.select.changed
        .listen((e) => print('@${Simulator.time}: Select Value changed: $e'));
    mux.out.changed
        .listen((e) => print('@${Simulator.time}: Out Value changed: $e'));
  }

  // Set the select value to 0, 1, 2, 3 over time
  Simulator.registerAction(27, () => select.put(0));
  Simulator.registerAction(37, () => select.put(1));
  Simulator.registerAction(47, () => select.put(2));
  Simulator.registerAction(57, () => select.put(3));

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

  await Simulator.simulationEnded;

  // We can take a look at the waves now.
  if (!noPrint) {
    print('To view waves, check out waves.vcd with a waveform viewer'
        ' (e.g. `gtkwave waves.vcd`).');
  }
}
