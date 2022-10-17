/// SPDX-License-Identifier: BSD-3-Clause
/// fir_filter.dart
/// A basic example of a FIR filter
///
/// 2022 February 02
/// Author: wswongat
///

// ignore_for_file: avoid_print

import 'dart:io';
import 'package:rohd/rohd.dart';

class FirFilter extends Module {
  // For convenience, map interesting outputs to short variable names for
  // consumers of this module
  Logic get out => output('out');

  // This Fir Filter supports any width and depth, defined at runtime
  final int bitWidth;
  final int depth;
  FirFilter(Logic en, Logic resetB, Logic clk, Logic inputVal, List<int> coef,
      {this.bitWidth = 16, super.name = 'FirFilter'})
      : depth = coef.length {
    // Register inputs and outputs of the module in the constructor
    // Module logic must consume registered inputs and output to
    // registered outputs
    if (depth < 1) {
      // Depth Check
      throw Exception('Depth parameter should more than 1');
    }
    // Add input/output port
    en = addInput('en', en);
    inputVal = addInput('inputVal', inputVal, width: bitWidth);
    resetB = addInput('resetB', resetB);
    clk = addInput('clk', clk);
    // Generate input train
    final z = List<Logic>.generate(
        depth, (index) => Logic(width: bitWidth, name: 'z$index'));

    // Generate output
    final out = addOutput('out', width: bitWidth);

    // Initialize conditionalAssign list
    final inputTrain = [z[0] < inputVal];
    var sum = z[0] * coef[0];
    for (var i = 0; i < z.length - 1; i++) {
      inputTrain.add(z[i + 1] < z[i]);
      sum = sum + z[i + 1] * coef[i + 1];
    }
    // The List above is represent the FIR filter
    // sum[n] =
    //    _z[n]*coef[n] + _z[n-1]*coef[n-1] + .... + _z[n-depth]*coef[n-depth]

    // `Sequential` is like SystemVerilog's always_ff,
    // in this case trigger on the positive edge of clk
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog
      // always blocks
      If(resetB,
          then: [
            // `If` is a conditional if statement, like `if` in SystemVerilog
            //  always blocks
            If(en, then: inputTrain + [out < sum], orElse: [
              // the '<' operator is a conditional assignment
              out < 0
            ])
          ],
          orElse: [
                // the '<' operator is a conditional assignment
                out < 0
                // Set all _z to zero
              ] +
              List<ConditionalAssign>.generate(depth, (index) => z[index] < 0))
    ]);
  }
}

Future<void> main({bool noPrint = false}) async {
  const sumWidth = 8;
  final en = Logic(name: 'en');
  final resetB = Logic(name: 'resetB');
  final inputVal = Logic(name: 'inputVal', width: sumWidth);

  final clk = SimpleClockGenerator(5).clk;
  // 4-cycle delay coefficients
  final firFilter =
      FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: sumWidth);

  await firFilter.build();

  // Generate systemverilog code to file
  final systemVerilogCode = firFilter.generateSynth();
  if (!noPrint) {
    // Print systemverilog code to console
    print(systemVerilogCode);
    // Save systemverilog code to file
    File('rtl.sv').writeAsStringSync(systemVerilogCode);
  }

  en.put(0);
  resetB.put(0);
  inputVal.put(1);

  // Attach a waveform dumper
  if (!noPrint) {
    WaveDumper(firFilter);
  }

  Simulator.registerAction(5, () => en.put(1));
  Simulator.registerAction(10, () => resetB.put(1));

  for (var i = 1; i < 10; i++) {
    Simulator.registerAction(5 + i * 4, () => inputVal.put(i));
  }

  // Print a message when we're done with the simulation!
  Simulator.registerAction(100, () {
    if (!noPrint) {
      print('Simulation completed!');
    }
  });

  // Set a maximum time for the simulation so it doesn't keep running forever
  Simulator.setMaxSimTime(100);

  // Kick off the simulation
  await Simulator.run();

  // We can take a look at the waves now
  if (!noPrint) {
    print('To view waves, check out waves.vcd with a'
        ' waveform viewer (e.g. `gtkwave waves.vcd`).');
  }
}
