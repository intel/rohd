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

    final val = addOutput('val', width: width);

    // A local signal named 'nextVal'.
    final nextVal = Logic(name: 'nextVal', width: width);

    // Assignment statement of nextVal to be val+1
    // ('<=' is the assignment operator).
    nextVal <= val + 1;

    // `Sequential` is like SystemVerilog's always_ff, in this case trigger on
    // the positive edge of clk.
    Sequential(clk, [
      // `If` is a conditional if statement, like `if` in SystemVerilog
      // always blocks.
      If(reset, then: [
        // The '<' operator is a conditional assignment.
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}

// Let's simulate with this counter a little, generate a waveform, and take a
// look at generated SystemVerilog.
Future<void> main({bool noPrint = false}) async {
  final a = Logic();
  a <= a;
}
