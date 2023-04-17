import 'package:rohd/rohd.dart';

class DFlipFlop extends Module {
  DFlipFlop(Logic data, Logic reset, Logic clk) {
    // declare input and output
    data = addInput('d', data);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);

    final q = addOutput('q');

    Sequential(clk, [
      If(reset, then: [q < 0], orElse: [q < data])
    ]);
  }

  Logic get q => output('q');
}

void main() async {
  final data = Logic();
  final reset = Logic();
  final clk = SimpleClockGenerator(10).clk;

  final dff = DFlipFlop(clk, data, reset);
  await dff.build();

  print(dff.generateSynth());

  // Add some checks
  // Start the Simulator and give maximum simulation time
}
