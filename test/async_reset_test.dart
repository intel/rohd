// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// async_reset_test.dart
// Tests for asynchronous resets and triggers
//
// 2024 December 16
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class NonIdenticalTriggerSeq extends Module {
  /// If [triggerAfterSampledUpdate] is `true`, then the trigger for the
  /// sequential block happens *after* the signal being sampled updates.  If
  /// [triggerAfterSampledUpdate] is `false`, then the trigger for the
  /// sequential block happens *before* the signal being sampled updates.
  NonIdenticalTriggerSeq(
    Logic trigger, {
    bool invert = false,
    bool triggerAfterSampledUpdate = true,
  }) {
    final clk = Logic(name: 'clk')..gets(Const(0));
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
  Logic get result => output('result');
  MultipleTriggerSeq(Logic trigger1, Logic trigger2, {bool withClock = false}) {
    final clk = Logic(name: 'clk')
      ..gets(withClock ? SimpleClockGenerator(10).clk : Const(0));
    trigger1 = addInput('trigger1', trigger1);
    trigger2 = addInput('trigger2', trigger2);

    addOutput('result', width: 8);

    Sequential.multi([
      clk,
      trigger1,
      trigger2
    ], [
      // this is bad style and possibly won't synthesize properly, but helps
      // test some of the checking in `Sequential`s
      If(trigger1, then: [
        If(trigger2, then: [
          result < 0xc,
        ], orElse: [
          result < 0xa,
        ]),
      ], orElse: [
        If(trigger2, then: [
          result < 0xb,
        ], orElse: [
          result < 0xd,
        ]),
      ]),
    ]);
  }
}

class ResetMod extends Module {
  Logic get val => output('val');
  ResetMod({
    required Logic? clk,
    required Logic reset,
    required void Function(Logic clk, Logic reset, Logic val) seqBuilder,
  }) {
    clk = clk == null ? SimpleClockGenerator(10).clk : addInput('clk', clk);
    reset = addInput('reset', reset);
    addOutput('val');

    seqBuilder(clk, reset, val);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('non-async reset samples non-async-ly', () {
    final seqMechanism = {
      'Sequential.multi no asyncReset': (Logic clk, Logic reset, Logic val) =>
          Sequential.multi(
            [clk],
            reset: reset,
            [
              val < 1,
            ],
          ),
      'Sequential with no asyncReset': (Logic clk, Logic reset, Logic val) =>
          Sequential(
            clk,
            reset: reset,
            [
              val < 1,
            ],
          ),
      'FlipFlop with no asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            FlipFlop(
              clk,
              reset: reset,
              Const(1),
            ).q;
      },
      'flop with no asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            flop(
              clk,
              reset: reset,
              Const(1),
            );
      },
    };

    for (final mechanism in seqMechanism.entries) {
      group('using ${mechanism.key}', () {
        test('simcompare no clk sync reset', () async {
          final mod = ResetMod(
            clk: Logic(name: 'clk'),
            reset: Logic(name: 'reset'),
            seqBuilder: mechanism.value,
          );

          await mod.build();

          final vectors = [
            Vector({'clk': 0, 'reset': 0}, {}),
            Vector({'clk': 1, 'reset': 0}, {'val': 1}),
            Vector({'clk': 1, 'reset': 0}, {'val': 1}),
            Vector({'clk': 1, 'reset': 1}, {'val': 1}),
            Vector({'clk': 1, 'reset': 1}, {'val': 1}),
          ];

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });

        test('simcompare with clk sync reset', () async {
          final mod = ResetMod(
            clk: null,
            reset: Logic(name: 'reset'),
            seqBuilder: mechanism.value,
          );

          await mod.build();

          final vectors = [
            Vector({'reset': 0}, {}),
            Vector({'reset': 0}, {'val': 1}),
            Vector({'reset': 0}, {'val': 1}),
            Vector({'reset': 1}, {'val': 1}),
            Vector({'reset': 1}, {'val': 0}),
          ];

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });
      });
    }
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
              Const(1),
              asyncReset: true,
            ).q;
      },
      'flop with asyncReset': (Logic clk, Logic reset, Logic val) {
        val <=
            flop(
              clk,
              reset: reset,
              Const(1),
              asyncReset: true,
            );
      },
    };

    for (final mechanism in seqMechanism.entries) {
      group('using ${mechanism.key}', () {
        test('functional', () async {
          final clk = Logic(name: 'clk');
          final reset = Logic(name: 'reset');
          final val = Logic(name: 'val');

          reset.inject(0);
          clk.inject(0);

          mechanism.value(clk, reset, val);

          Simulator.registerAction(10, () {
            clk.put(1);
          });

          Simulator.registerAction(11, () {
            expect(val.value.toInt(), 1);
          });

          Simulator.registerAction(14, () {
            reset.put(1);
          });

          Simulator.registerAction(15, () {
            expect(val.value.toInt(), 0);
          });

          await Simulator.run();
        });

        test('simcompare', () async {
          final mod = ResetMod(
            clk: Logic(name: 'clk'),
            reset: Logic(name: 'reset'),
            seqBuilder: mechanism.value,
          );

          await mod.build();

          final vectors = [
            Vector({'clk': 0, 'reset': 0}, {}),
            Vector({'clk': 1, 'reset': 0}, {'val': 1}),
            Vector({'clk': 1, 'reset': 0}, {'val': 1}),
            Vector({'clk': 1, 'reset': 1}, {'val': 0}),
            Vector({'clk': 1, 'reset': 1}, {'val': 0}),
          ];

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });
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
    reset.inject(1);

    Simulator.registerAction(Simulator.time + 1, () {
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

      final vectorsRohd = [
        Vector({'trigger': 0}, {}),
        // ROHD catches a bad race condition
        Vector({'trigger': 1}, {'result': 'x'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsRohd);

      final vectorsSv = [
        Vector({'trigger': 0}, {}),
        Vector({'trigger': 1}, {'result': 1}),
      ];

      SimCompare.checkIverilogVector(mod, vectorsSv);
    });

    test('inverted', () async {
      final mod = NonIdenticalTriggerSeq(Logic(), invert: true);

      await mod.build();

      final vectorsRohd = [
        Vector({'trigger': 1}, {}),
        // ROHD catches a bad race condition
        Vector({'trigger': 0}, {'result': 'x'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsRohd);

      final vectorsSv = [
        Vector({'trigger': 1}, {}),
        Vector({'trigger': 0}, {'result': 0}),
      ];

      SimCompare.checkIverilogVector(mod, vectorsSv);
    });

    test('trigger earlier inverted', () async {
      final mod = NonIdenticalTriggerSeq(Logic(),
          invert: true, triggerAfterSampledUpdate: false);

      await mod.build();

      final vectorsRohd = [
        Vector({'trigger': 0}, {}),
        // ROHD catches a bad race condition
        Vector({'trigger': 1}, {'result': 'x'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsRohd);

      final vectorsSv = [
        Vector({'trigger': 0}, {}),
        // in this case, the trigger happened before the sampled value updated
        Vector({'trigger': 1}, {'result': 1}),
      ];

      SimCompare.checkIverilogVector(mod, vectorsSv);
    });

    test('trigger earlier normal', () async {
      final mod =
          NonIdenticalTriggerSeq(Logic(), triggerAfterSampledUpdate: false);

      await mod.build();

      final vectorsRohd = [
        Vector({'trigger': 0}, {}),
        // ROHD catches a bad race condition
        Vector({'trigger': 1}, {'result': 'x'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsRohd);

      final vectorsSv = [
        Vector({'trigger': 0}, {}),
        // in this case, the two signals are "identical", so there is no "later"
        Vector({'trigger': 1}, {'result': 1}),
      ];

      SimCompare.checkIverilogVector(mod, vectorsSv);
    });
  });

  group('multiple trigger races', () {
    group('two resets simulatenously', () {
      for (final withClock in [true, false]) {
        test('withClock=$withClock', () async {
          final mod =
              MultipleTriggerSeq(Logic(), Logic(), withClock: withClock);

          await mod.build();

          final vectors = [
            Vector({'trigger1': 0, 'trigger2': 0}, {}),
            Vector({'trigger1': 1, 'trigger2': 1}, {}),
            Vector({'trigger1': 1, 'trigger2': 1}, {'result': 0xc}),
          ];

          // make sure change happend right on the edges
          Simulator.registerAction(12, () {
            expect(mod.result.value.toInt(), 0xc);
          });

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });
      }
    });

    test('one then another trigger post-changed', () async {
      final a = Logic()..put(0);
      final b = Logic()..put(0);

      final result = Logic(width: 8);

      Sequential.multi([
        a,
        b
      ], [
        // this is bad style and possibly won't synthesize properly, but helps
        // test some of the checking in `Sequential`s
        If.s(
          a,
          If.s(
            b,
            result < 0xc,
            result < 0xa,
          ),
          If.s(
            b,
            result < 0xb,
            result < 0xc,
          ),
        ),
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

  test(
      'put at simulation start before trigger changed '
      'does not cause race x generation', () async {
    final d = Logic();
    final clk = SimpleClockGenerator(10).clk;

    final q = flop(clk, d);

    unawaited(Simulator.run());

    d.put(1);

    await clk.nextPosedge;

    expect(q.value.isValid, isTrue);
    expect(q.value.toInt(), 1);

    d.put(0);

    await clk.nextPosedge;

    expect(q.value.toInt(), 0);

    await Simulator.endSimulation();
  });

  test('async trigger and inputs change but does not affect result, no x',
      () async {
    final trigger1 = Logic()..put(0);
    final trigger2 = Logic()..put(0);
    final otherInput = Logic(width: 8)..put(0xcd);
    final result = Logic(width: 8);

    Sequential.multi([
      trigger1,
      trigger2,
    ], [
      If(trigger1, then: [
        result < 0xab,
      ], orElse: [
        result < otherInput,
      ]),
    ]);

    Simulator.registerAction(10, () {
      otherInput.put(0xef);
      trigger1.put(1);
    });

    Simulator.registerAction(11, () {
      // this trigger should be *fine* because the value of `result` is not
      // dependent on any of the other changing inputs
      expect(result.value.toInt(), 0xab);
    });

    Simulator.registerAction(20, () {
      trigger1.put(0);
    });

    Simulator.registerAction(30, () {
      trigger2.put(1);
      otherInput.put(0x34);
    });

    Simulator.registerAction(31, () {
      // this trigger is bad because otherInput and trigger2 changed
      // simultaneously, so its ambiguous what should be done
      expect(result.value, LogicValue.of('xxxxxxxx'));
    });

    Simulator.registerAction(40, () {
      trigger2.put(0);
    });

    Simulator.registerAction(50, () {
      // now otherInput doesn't change at all, make sure it recovers
      trigger1.put(1);
    });

    Simulator.registerAction(51, () {
      expect(result.value.toInt(), 0xab);
    });

    await Simulator.run();
  });

  test('async input x injection is cleaned up next edge', () async {
    final reset = Logic()..put(0);
    final clk = Logic()..put(1);
    final nextResult = Logic(width: 8)..put(0x11);
    final result = Logic(width: 8);

    Sequential.multi([
      clk,
      reset
    ], [
      If(reset, then: [
        result < 0,
      ], orElse: [
        result < nextResult,
      ]),
    ]);

    Simulator.registerAction(10, () {
      // trigger an X generation due to trigger & non-trigger simultaneous
      reset.put(1);
      nextResult.put(0x22);
    });

    Simulator.registerAction(11, () {
      expect(result.value.toInt(), 0);
    });

    Simulator.registerAction(20, () {
      reset.put(0);
    });

    Simulator.registerAction(30, () {
      clk.put(0);
    });

    Simulator.registerAction(40, () {
      // trigger the flop, but don't change the inputs
      clk.put(1);
    });

    Simulator.registerAction(41, () {
      // should get the new value (NOT X)
      expect(result.value.toInt(), 0x22);
    });

    await Simulator.run();
  });
}
