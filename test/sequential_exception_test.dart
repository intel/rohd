import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

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

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on the positive edge of clk
    Sequential(clk, [
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

void main() {
  group('Given a signal', () {
    test('When driven by two drivers in sequential block', () async {
      // Then its should throw an exception
      // Define some local signals.
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');

      // Generate a simple clock.  This will run along by itself as
      // the Simulator goes.
      final clk = SimpleClockGenerator(10).clk;

      // Build a counter.
      final counter = Counter(en, reset, clk);
      await counter.build();

      final systemVerilogCode = counter.generateSynth();
      File('temp.sv').writeAsStringSync(systemVerilogCode);
    });
  });
}
