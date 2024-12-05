import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class NonIdenticalTriggerSeq extends Module {
  NonIdenticalTriggerSeq(Logic trigger) {
    final clk = Logic(name: 'clk');
    trigger = addInput('trigger', trigger);

    final innerTrigger = Logic(name: 'innerTrigger', naming: Naming.reserved);
    innerTrigger <= trigger;

    final result = addOutput('result');

    Sequential.multi([
      clk,
      innerTrigger
    ], [
      result < trigger,
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('async reset samples correct reset value', () {
    final seqMechanism = {
      'Sequential.multi': (Logic clk, Logic reset, Logic val) =>
          Sequential.multi(
            [clk, reset],
            reset: reset,
            [
              val < 1,
            ],
          ),
      'Sequential with asyncReset': (Logic clk, Logic reset, Logic val) =>
          Sequential(
            clk,
            reset: reset,
            [
              val < 1,
            ],
            asyncReset: true,
          ),
      'FlipFlop with asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            FlipFlop(
              clk,
              reset: reset,
              val,
              asyncReset: true,
            ).q;
      },
      'flop with asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            flop(
              clk,
              reset: reset,
              val,
              asyncReset: true,
            );
      },
    };

    //TODO: what if there's another (connected) version of that signal that's the trigger?? but not exactly the same logic?
    //TODO: how to deal with injects that trigger edges??

    //TODO: doc clearly the behavior of sampling async triggersl

    for (final mechanism in seqMechanism.entries) {
      test('using ${mechanism.key}', () async {
        final clk = Logic(name: 'clk');
        final reset = Logic(name: 'reset');
        final val = Logic(name: 'val');

        reset.inject(0);
        clk.inject(0);

        mechanism.value(clk, reset, val);

        Simulator.registerAction(10, () {
          clk.put(1);
        });

        Simulator.registerAction(14, () {
          reset.put(1);
        });

        Simulator.registerAction(15, () {
          expect(val.value.toInt(), 0);
        });

        await Simulator.run();
      });
    }
  });

  test('non-identical signal trigger', () async {
    final mod = NonIdenticalTriggerSeq(Logic());

    await mod.build();

    final vectors = [
      Vector({'trigger': 0}, {}),
      Vector({'trigger': 1}, {'result': 1}),
    ];

    // await SimCompare.checkFunctionalVector(mod, vectors); //TODO fix
    SimCompare.checkIverilogVector(mod, vectors,
        dontDeleteTmpFiles: true, dumpWaves: true);
  });

  //TODO: test async reset with clocks too
}
