import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class ShiftRegister extends Module {
  Logic get sout => output('sout');
  ShiftRegister(Logic clk, Logic reset, Logic sin,
      {super.name = 'shift_register'}) {
    clk = addInput('clk', clk);
    reset = addInput(reset.name, reset);
    sin = addInput(sin.name, sin, width: sin.width);

    // output width: Let say, we want 8 bit register
    const regWidth = 8;
    final sout = addOutput('sout', width: regWidth);

    // Local signal
    final data = Logic(name: 'data', width: regWidth); // 0000

    Sequential(clk, [
      IfBlock([
        Iff(reset, [data < 0]),
        Else([
          data < [data.slice(regWidth - 2, 0), sin].swizzle() // left shift
        ])
      ]),
    ]);

    sout <= data;
  }
}

void main() async {
  test('check for value shift', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final sin = Logic(name: 'sin');

    final shiftReg = ShiftRegister(clk, reset, sin);
    await shiftReg.build();

    reset.inject(1);
    sin.inject(0);

    void printFlop([String message = '']) {
      print('@t=${Simulator.time}:\t'
          ' input=${sin.value}, output '
          '=${shiftReg.sout.value.toString(includeWidth: false)}\t$message');
    }

    // set a max time in case something goes longer
    Simulator.setMaxSimTime(100);
    unawaited(Simulator.run());

    WaveDumper(shiftReg,
        outputPath: 'doc/tutorials/chapter_7/shift_register.vcd');

    printFlop('Before');

    await clk.nextPosedge;
    reset.put(0);
    sin.put(1);

    // kick-off the simulator, but we don't want to wait
    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00000001'));

    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00000011'));

    await clk.nextPosedge;
    sin.put(0);
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00000111'));

    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00001110'));

    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00011100'));

    await clk.nextPosedge;
    sin.put(1);
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('00111000'));

    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('01110001'));

    await clk.nextPosedge;
    printFlop();
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('11100011'));

    await clk.nextPosedge;
    printFlop('Final');
    expect(
        shiftReg.sout.value.toString(includeWidth: false), equals('11000111'));

    // we're done, we can end the Simulation
    Simulator.endSimulation();

    await Simulator.simulationEnded;
  });
}
