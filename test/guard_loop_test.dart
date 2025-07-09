import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/scaffolding.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('guard loop', () async {
    final clk = SimpleClockGenerator(10).clk;

    final x = Logic(name: 'x');
    final y = Logic(name: 'y');

    Combinational([
      Case(Logic(name: 'expression'), [
        CaseItem(Logic(name: 'caseItem'), [
          y < x,
        ])
      ])
    ]);

    Simulator.setMaxSimTime(100000 * 10);

    //TODO: bug, signals that never change but are guarded grow forever!!

    unawaited(Simulator.run());

    for (var i = 0; i < 20; i++) {
      await clk.nextPosedge;
      x.put(i.isEven);
    }

    await Simulator.endSimulation();
  });
}
