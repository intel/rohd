// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// changed_test.dart
// Unit tests for Logic change events
//
// 2021 November 5
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('single changed multiple injections', () async {
    final a = Logic()..put(0);

    final b = Logic()..put(0);

    var numChangesDetected = 0;

    a.changed.listen((event) {
      numChangesDetected++;
    });

    a.posedge.listen((event) {
      b.inject(1);
    });

    Simulator.registerAction(10, () => a.put(1));

    await Simulator.run();

    expect(numChangesDetected, equals(1));
  });

  group('across simulator reset', () {
    Future<void> testAcrossSimulatorResets(Logic a) async {
      var numChangesDetected = 0;

      a.changed.listen((event) {
        numChangesDetected++;
        expect(event.newValue, event.previousValue + 1);
      });

      a.glitch.listen((args) {});

      Simulator.registerAction(10, () => a.put(1));

      await Simulator.run();

      expect(numChangesDetected, 1);

      await Simulator.reset();

      expect(a.value.toInt(), 1);

      // should *not* trigger a change, didn't change!
      Simulator.registerAction(20, () => a.put(1));

      await Simulator.run();

      expect(numChangesDetected, 1);

      await Simulator.reset();

      expect(a.value.toInt(), 1);

      // *should* trigger a change
      Simulator.registerAction(30, () => a.put(2));
      Simulator.registerAction(40, () => a.put(3));

      await Simulator.run();

      expect(a.value.toInt(), 3);

      expect(numChangesDetected, 3);
    }

    test('normal logic', () async {
      final a = Logic(width: 8)..put(0);

      await testAcrossSimulatorResets(a);
    });

    test('logic structure', () async {
      final a = LogicStructure([Logic(), Logic()])..put(0);

      await testAcrossSimulatorResets(a);
    });
  });

  test('changed does not trigger first time if no change', () async {
    final a = Logic()..put(1);

    var numChangesDetected = 0;

    a.changed.listen((event) {
      numChangesDetected++;
    });

    Simulator.registerAction(10, () => a.put(1));
    Simulator.registerAction(20, () => a.put(1));

    await Simulator.run();

    expect(numChangesDetected, 0);
  });

  test('clk edge counter', () async {
    final clk = SimpleClockGenerator(10).clk;
    final b = Logic();

    var val = false;
    clk.negedge.listen((event) async {
      b.inject(val);
      val = !val;
    });

    final uniquePosedgeTimestamps = <int>{};
    var count = 0;
    clk.posedge.listen((event) {
      uniquePosedgeTimestamps.add(Simulator.time);
      count++;
    });

    Simulator.setMaxSimTime(100);
    await Simulator.run();

    expect(count, equals(uniquePosedgeTimestamps.length));
  });

  test('injection triggers edge', () async {
    final a = Logic()..put(0);

    var numPosedges = 0;
    a.posedge.listen((event) {
      numPosedges += 1;
    });

    a.inject(1);

    await Simulator.run();

    expect(numPosedges, equals(1));
  });

  test('injection can trigger multiple changed events if post tick', () async {
    final a = Logic(width: 8)..put(0);

    Simulator.registerAction(10, () {
      a
        ..put(1)
        ..inject(2);
    });

    a.changed.listen((_) {
      a.inject(a.value.toInt() | (1 << 4));
    });

    final seenValues = <LogicValue>[];

    a.changed.listen((_) {
      seenValues.add(a.value);
    });

    await Simulator.run();

    expect(seenValues.length, 2);
    expect(seenValues[0].toInt(), 2);
    expect(seenValues[1].toInt(), 2 | (1 << 4));
  });

  group('injection triggers flop', () {
    Future<void> injectionTriggersFlop({required bool useArrays}) async {
      final baseClk = SimpleClockGenerator(10).clk;

      Logic genSignal() => useArrays ? LogicArray([1], 1) : Logic();

      final clk = genSignal();
      final d = genSignal();

      final q = genSignal()..gets(FlipFlop(clk, d).q);

      var qHadPosedge = false;

      Simulator.setMaxSimTime(100);

      unawaited(q.nextPosedge.then((value) {
        qHadPosedge = true;
      }));

      unawaited(Simulator.run());

      await baseClk.nextPosedge;
      clk.inject(0);
      d.inject(0);
      await baseClk.nextPosedge;
      clk.inject(1);
      await baseClk.nextPosedge;
      expect(q.value, equals(LogicValue.zero));
      clk.inject(0);
      d.inject(1);
      await baseClk.nextPosedge;
      clk.inject(1);
      await baseClk.nextPosedge;
      expect(q.value, equals(LogicValue.one));

      await Simulator.simulationEnded;

      expect(qHadPosedge, equals(true));
    }

    test('normal logic', () async {
      await injectionTriggersFlop(useArrays: false);
    });

    test('arrays', () async {
      await injectionTriggersFlop(useArrays: true);
    });
  });

  test('injection triggers flop with enable logicvalue 1', () async {
    final baseClk = SimpleClockGenerator(10).clk;

    final clk = Logic();
    final d = Logic();
    final en = Logic();
    final q = FlipFlop(clk, d, en: en).q;

    var qHadPosedge = false;

    Simulator.setMaxSimTime(100);

    unawaited(q.nextPosedge.then((value) {
      qHadPosedge = true;
    }));

    unawaited(Simulator.run());

    await baseClk.nextPosedge;
    en.inject(1);
    clk.inject(0);
    d.inject(0);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.zero));
    en.inject(1);
    clk.inject(0);
    d.inject(1);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.one));

    await Simulator.simulationEnded;

    expect(qHadPosedge, equals(true));
  });

  test('injection triggers flop with enable', () async {
    final baseClk = SimpleClockGenerator(10).clk;

    final clk = Logic();
    final d = Logic();
    final en = Logic();
    final q = FlipFlop(clk, d, en: en).q;

    var qHadPosedge = false;

    Simulator.setMaxSimTime(100);

    unawaited(q.nextPosedge.then((value) {
      qHadPosedge = true;
    }));

    unawaited(Simulator.run());

    await baseClk.nextPosedge;
    en.inject(1);
    clk.inject(0);
    d.inject(0);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.zero));
    en.inject(0);
    clk.inject(0);
    d.inject(1);
    await baseClk.nextPosedge;
    clk.inject(1);
    await baseClk.nextPosedge;
    expect(q.value, equals(LogicValue.zero));

    await Simulator.simulationEnded;

    expect(qHadPosedge, equals(false));
  });

  test('reconnected signal still hits changed events', () async {
    final a = Logic(name: 'a');
    final b = Logic(name: 'b');

    var detectedAChanged = false;
    a.changed.listen((event) {
      detectedAChanged = true;
    });

    a <= b;

    Simulator.registerAction(100, () {
      b.put(1);
    });

    await Simulator.run();

    expect(detectedAChanged, isTrue);
  });

  test('chain of reconnected signals still changes', () async {
    final a = Logic(name: 'a');
    final b = Logic(name: 'b');
    final c = Logic(name: 'c');

    var detectedAChanged = false;
    a.changed.listen((event) {
      detectedAChanged = true;
    });

    a <= b;
    b <= c;

    Simulator.registerAction(100, () {
      c.put(1);
    });

    await Simulator.run();

    expect(detectedAChanged, isTrue);
  });

  test('chain of reconnected signals still glitches', () async {
    final a = Logic(name: 'a');
    final b = Logic(name: 'b');
    final c = Logic(name: 'c');

    a.put(0);

    a <= b;
    b <= c;

    c.put(1);

    expect(a.value, equals(LogicValue.one));
  });

  test('late connection propagates without put', () async {
    final a = Logic(name: 'a');
    final b = ~a;
    a <= Const(0);
    expect(b.value, equals(LogicValue.one));
  });

  test('injection on edge happens on same edge', () async {
    final clk = SimpleClockGenerator(200).clk;

    // faster clk just to add more events to the Simulator
    SimpleClockGenerator(17).clk;

    final posedgeChangingSignal = Logic()..put(0);
    final negedgeChangingSignal = Logic()..put(0);

    void posedgeExpect() {
      if (Simulator.time > 50) {
        expect((Simulator.time + 100) % 200, equals(0));
      }
    }

    void negedgeExpect() {
      if (Simulator.time > 50) {
        expect(Simulator.time % 200, equals(0));
      }
    }

    clk.posedge.listen((event) {
      posedgeExpect();
      posedgeChangingSignal.inject(~posedgeChangingSignal.value);
    });
    clk.negedge.listen((event) {
      negedgeChangingSignal.inject(~negedgeChangingSignal.value);
    });

    posedgeChangingSignal.glitch.listen((args) {
      posedgeExpect();
    });
    negedgeChangingSignal.glitch.listen((args) {
      negedgeExpect();
    });

    posedgeChangingSignal.changed.listen((args) {
      posedgeExpect();
    });
    negedgeChangingSignal.changed.listen((args) {
      negedgeExpect();
    });

    Simulator.setMaxSimTime(5000);
    await Simulator.run();
  });

  test('chain of changed and injects', () async {
    final a = Logic()..put(0);
    final b = Logic()..put(0);
    final c = Logic()..put(0);
    final d = Logic()..put(0);

    var changeCount = 0;

    a.changed.listen((event) {
      b.inject(~b.value);
    });

    b.changed.listen((event) {
      c.inject(~c.value);
    });

    c.changed.listen((event) {
      d.inject(~d.value);
    });

    d.changed.listen((event) {
      changeCount++;
    });

    Simulator.registerAction(10, () => a.put(~a.value));
    Simulator.registerAction(20, () => a.put(~a.value));

    Simulator.setMaxSimTime(500);

    await Simulator.run();

    expect(changeCount, 2);
  });
}
