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
    final sin = Logic(name: 'sin', width: 1);

    final shiftReg = ShiftRegister(clk, reset, sin);
    await shiftReg.build();
    print(shiftReg.generateSynth());

    reset.inject(1);
    sin.inject(0);

    // set a max time in case something goes longer
    Simulator.setMaxSimTime(100);

    // kick-off the simulator, but we don't want to wait
    unawaited(Simulator.run());
    await clk.nextPosedge;
    print(shiftReg.sout.value.toString(includeWidth: false));
  });
}
