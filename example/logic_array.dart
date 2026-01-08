// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// A very basic example of a Logic Array module
// to show case the selectIndex and selectFrom
//
// 2025 March 04
// Author: Ramli, Nurul Izziany <nurul.izziany.ramli@intel.com>

// Though we usually avoid them, for this example,
// allow `print` messages (disable lint):
// ignore_for_file: avoid_print

// Import necessary dart packages for this file.
import 'dart:async';

// Import the ROHD package.
import 'package:rohd/rohd.dart';

class LogicArrayExample extends Module {
  Logic get index => input('index');
  Logic get selectIndexValue => output('selectIndexValue');
  Logic get selectFromValue => output('selectFromValue');

  LogicArrayExample(LogicArray arrayA, Logic index, Logic selectIndexValue,
      Logic selectFromValue)
      : super(name: 'logic_array_example') {
    //
    arrayA = addInputArray('arrayA', arrayA,
        dimensions: arrayA.dimensions, elementWidth: arrayA.elementWidth);
    index = addInput('index', index, width: index.width);
    selectIndexValue =
        addOutput('selectIndexValue', width: arrayA.elementWidth);
    selectFromValue = addOutput('selectFromValue', width: arrayA.elementWidth);

    final defaultValue = Const(0, width: arrayA.elementWidth);

    // Use selectIndex or selectFrom to select a value from an array
    selectIndexValue <=
        arrayA.elements.selectIndex(index, defaultValue: defaultValue);
    selectFromValue <=
        index.selectFrom(arrayA.elements, defaultValue: defaultValue);
  }
}

Future<void> main({bool noPrint = false}) async {
  // Define local signals
  final arrayA =
      LogicArray([4], 8, name: 'arrayA'); // A 1D array with 4 8-bit elements
  final id = Logic(name: 'id', width: 3);
  final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
  final selectFromValue = Logic(name: 'selectFromValue', width: 8);

  final logicArrayExample =
      LogicArrayExample(arrayA, id, selectIndexValue, selectFromValue);

  // Build the module
  await logicArrayExample.build();

  final systemVerilogCode = logicArrayExample.generateSynth();
  if (!noPrint) {
    print(systemVerilogCode);
  }

  // Simulate the module
  if (!noPrint) {
    WaveDumper(logicArrayExample);
  }

  // Set the input values
  arrayA.elements[0].inject(1);
  arrayA.elements[1].inject(2);
  arrayA.elements[2].inject(3);
  arrayA.elements[3].inject(4);

  // Print a message when the id and the outputs value changes
  if (!noPrint) {
    logicArrayExample.index.changed
        .listen((e) => print('@${Simulator.time}: ID Value changed: $e'));
    logicArrayExample.selectIndexValue.changed.listen(
        (e) => print('@${Simulator.time}: SelectIndex Value changed: $e'));
    logicArrayExample.selectFromValue.changed.listen(
        (e) => print('@${Simulator.time}: SelectFrom Value changed: $e'));
  }

  // Set the index value to 0, 1, 2, 3 over time
  Simulator.registerAction(27, () => id.put(0));
  Simulator.registerAction(37, () => id.put(1));
  Simulator.registerAction(47, () => id.put(2));
  Simulator.registerAction(57, () => id.put(3));
  Simulator.registerAction(67, () => id.put(4));

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
