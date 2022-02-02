/// SPDX-License-Identifier: BSD-3-Clause
/// fir_filter.dart
/// A basic example of a FIR filter
///
/// 2022 February 02
/// Author: wswongat
///
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class FirFilter extends Module {
  // For convenience, map interesting outputs to short variable names for consumers of this module
  Logic get out => output('out');

  // This Fir Filter supports any width and depth, defined at runtime
  final int bitWidth;
  final int depth;
  FirFilter(Logic en, Logic reset, Logic clk, Logic inputVal, List<int> coef,
      {this.bitWidth = 16, name = 'FirFilter'})
      : depth = coef.length,
        super(name: name) {
    // Register inputs and outputs of the module in the constructor.
    // Module logic must consume registered inputs and output to registered outputs.
    if (depth < 1) {
      // Depth Check
      throw Exception('Depth parameter should more than 1');
    }
    // Add input/output port
    en = addInput('en', en);
    inputVal = addInput('inputVal', inputVal, width: bitWidth);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    // Generate input train
    List<Logic> _z = List<Logic>.generate(
        depth, (index) => Logic(width: bitWidth, name: 'z$index'));

    // Generate output
    var out = addOutput('out', width: bitWidth);

    // Initialize conditionalAssign list
    List<ConditionalAssign> inputTrain = [_z[0] < inputVal];
    var sum = _z[0] * coef[0];
    for (int i = 0; i < _z.length - 1; i++) {
      inputTrain.add(_z[i + 1] < _z[i]);
      sum = sum + _z[i + 1] * coef[i + 1];
    }
    // The List above is represent the FIR filter.
    // sum[n] = _z[n]*coef[n] + _z[n-1]*coef[n-1] + .... + _z[n-depth]*coef[n-depth]

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on the positive edge of clk
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog always blocks
      If(reset, then: [
        // `If` is a conditional if statement, like `if` in SystemVerilog always blocks
        If(en, then: inputTrain + [out < sum], orElse: [
          // the '<' operator is a conditional assignment
          out < 0
        ])
      ], orElse: [
        // the '<' operator is a conditional assignment
        out < 0
      ])
    ]);
  }
}

Future<void> main({bool noPrint = false}) async {
  if (Simulator.time != 0) {
    await Simulator.reset();
  }

  var sumWidth = 8;
  var en = Logic(name: 'en'),
      rst = Logic(name: 'en'),
      inputVal = Logic(name: 'en', width: sumWidth);

  var clk = SimpleClockGenerator(5).clk;
  // 4-cycle delay coefficients
  var firFilter =
      FirFilter(en, rst, clk, inputVal, [0, 0, 0, 1], bitWidth: sumWidth);

  await firFilter.build();

  // Generate systemverilog code to file.
  var systemVerilogCode = firFilter.generateSynth();
  if (!noPrint) print(systemVerilogCode);
  // Save systemverilog code to file.
  // var file = File('rtl.sv');
  // var sink = file.openWrite();
  // sink.write(systemVerilogCode);
  // sink.close();

  en.put(0);
  rst.put(0);
  inputVal.put(1);

  // Attach a waveform dumper
  WaveDumper(firFilter);

  Simulator.registerAction(5, () => en.put(1));
  Simulator.registerAction(10, () => rst.put(1));

  for (int i = 1; i < 10; i++) {
    Simulator.registerAction(5 + i * 4, () => inputVal.put(i));
  }

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
