import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class NonIdenticalTriggerSeq extends Module {
  /// If [triggerAfterSampledUpdate] is `true`, then the trigger for the
  /// sequential block happens *afer* the signal being sampled updates.  If
  /// [triggerAfterSampledUpdate] is `false`, then the trigger for the
  /// sequential block happens *before* the signal being sampled updates.
  NonIdenticalTriggerSeq(
    Logic trigger, {
    bool invert = false,
    bool triggerAfterSampledUpdate = true,
  }) {
    final clk = Logic(name: 'clk');
    trigger = addInput('trigger', trigger);

    final innerTrigger = Logic(name: 'innerTrigger', naming: Naming.reserved);
    innerTrigger <= (invert ? ~trigger : trigger);

    final result = addOutput('result');

    Sequential.multi([
      clk,
      if (triggerAfterSampledUpdate) innerTrigger else trigger,
    ], [
      result < (triggerAfterSampledUpdate ? trigger : innerTrigger),
    ]);
  }
}

class MultipleTriggerSeq extends Module {
  MultipleTriggerSeq(Logic trigger1, Logic trigger2) {
    final clk = Logic(); //SimpleClockGenerator(10).clk;
    trigger1 = addInput('trigger1', trigger1);
    trigger2 = addInput('trigger2', trigger2);

    final result = addOutput('result', width: 8);

    Sequential.multi([
      clk,
      trigger1,
      trigger2
    ], [
      If.block([
        Iff(trigger1 & ~trigger2, [result < 0xa]),
        ElseIf(~trigger1 & trigger2, [result < 0xb]),
        // ElseIf(trigger1 & trigger2, [result < 0xc]),
        ElseIf(~trigger1 & ~trigger2, [result < 0xd]),
      ]),
      // result < (trigger1 & trigger2),
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

  test('async reset triggered via injection after clk edge still triggers',
      () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset')..inject(0);
    final val = Logic(name: 'val');

    Sequential(clk, reset: reset, asyncReset: true, [
      val < 1,
    ]);

    Simulator.setMaxSimTime(1000);
    unawaited(Simulator.run());

    await clk.nextPosedge;
    await clk.nextPosedge;
    // reset.inject(1); //TODO
    Simulator.injectAction(() {
      // print('asdf1');
      reset.put(1);
    });

    Simulator.registerAction(Simulator.time + 1, () {
      // print('asdf');
      expect(val.value.toInt(), 0);
    });

    // one more edge so sim doesnt end immediately
    await clk.nextPosedge;

    await Simulator.endSimulation();
  });

  group('non-identical signal trigger', () {
    test('normal', () async {
      final mod = NonIdenticalTriggerSeq(Logic());

      await mod.build();

      final vectors = [
        Vector({'trigger': 0}, {}),
        Vector({'trigger': 1}, {'result': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors); //TODO fix
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('inverted', () async {
      final mod = NonIdenticalTriggerSeq(Logic(), invert: true);

      await mod.build();

      final vectors = [
        Vector({'trigger': 1}, {}),
        Vector({'trigger': 0}, {'result': 0}),
      ];

      // await SimCompare.checkFunctionalVector(mod, vectors); //TODO fix
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('trigger earlier inverted', () async {
      final mod = NonIdenticalTriggerSeq(Logic(),
          invert: true, triggerAfterSampledUpdate: false);

      await mod.build();

      final vectors = [
        Vector({'trigger': 0}, {}),
        // in this case, the trigger happened before the sampled value updated
        Vector({'trigger': 1}, {'result': 1}),
      ];

      // await SimCompare.checkFunctionalVector(mod, vectors); //TODO fix
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('trigger earlier normal', () async {
      final mod =
          NonIdenticalTriggerSeq(Logic(), triggerAfterSampledUpdate: false);

      await mod.build();

      final vectors = [
        Vector({'trigger': 0}, {}),
        // in this case, the two signals are "identical", so there is no "later"
        Vector({'trigger': 1}, {'result': 1}),
      ];

      // await SimCompare.checkFunctionalVector(mod, vectors); //TODO fix
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  //TODO: test async reset with clocks too

  //TODO: test if registerAction (same tick) with clk and reset both edges at the same time
  // what should that even do?? error?? what if two signals other than clk (like different resets)
  // that need to be mutually exclusive happen?
  // always@(clk, r1, r2) if(r1 & ~r2) ... if(r2 & ~r1) ... if(r1 & r2) ... if(~r1 & ~r2) ...

  group('multiple trigger races', () {
    test('two resets simulatenously', () async {
      final mod = MultipleTriggerSeq(Logic(), Logic());

      await mod.build();

      final vectors = [
        Vector({'trigger1': 0, 'trigger2': 0}, {}),
        // Vector({'trigger1': 0, 'trigger2': 0}, {'result': 0xd}),
        Vector({'trigger1': 1, 'trigger2': 1}, {}),
        Vector({'trigger1': 1, 'trigger2': 1}, {'result': 0xd}),
      ];

      //TODO fix, should this fail?
      // await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('one then another trigger post-changed', () async {
      final a = Logic()..put(0);
      final b = Logic()..put(0);

      final result = Logic(width: 8);

      Sequential.multi([
        a,
        b
      ], [
        If.block([
          Iff(a & ~b, [result < 0xa]),
          ElseIf(~a & b, [result < 0xb]),
          Else([result < 0xc]),
        ]),
      ]);

      Simulator.registerAction(10, () {
        a.put(1);
      });

      a.changed.listen((_) {
        Simulator.injectAction(() {
          a.put(0);
          b.put(1);
        });
      });

      final seenValues = <LogicValue>[];

      result.changed.listen((_) {
        expect(Simulator.time, 10);
        seenValues.add(result.value);
      });

      await Simulator.run();

      expect(seenValues.length, 2);
      expect(seenValues[0].toInt(), 0xa);
      expect(seenValues[1].toInt(), 0xb);
    });
  });
}
