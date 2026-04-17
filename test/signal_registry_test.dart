// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_registry_test.dart
// Tests for Module canonical naming (SignalNamer / signalName / allocateSignalName).
//
// 2026 April 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/filter_bank.dart';

// ────────────────────────────────────────────────────────────────
// Simple test modules
// ────────────────────────────────────────────────────────────────

class _GateMod extends Module {
  _GateMod(Logic a, Logic b) : super(name: 'gatetestmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final aBar = addOutput('a_bar');
    final aAndB = addOutput('a_and_b');
    aBar <= ~a;
    aAndB <= a & b;
  }
}

class _Counter extends Module {
  _Counter(Logic en, Logic reset, {int width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    final val = addOutput('val', width: width);
    final nextVal = Logic(name: 'nextVal', width: width);
    nextVal <= val + 1;
    Sequential.multi([
      SimpleClockGenerator(10).clk,
      reset,
    ], [
      If(reset, then: [
        val < 0,
      ], orElse: [
        If(en, then: [val < nextVal]),
      ]),
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('signalName basics', () {
    test('returns port names after build', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(mod.signalName(mod.input('a')), equals('a'));
      expect(mod.signalName(mod.input('b')), equals('b'));
      expect(mod.signalName(mod.output('a_bar')), equals('a_bar'));
      expect(mod.signalName(mod.output('a_and_b')), equals('a_and_b'));
    });

    test('returns internal signal names', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      expect(mod.signalName(mod.input('en')), equals('en'));
      expect(mod.signalName(mod.input('reset')), equals('reset'));
      expect(mod.signalName(mod.output('val')), equals('val'));
    });
  });

  group('allocateSignalName', () {
    test('avoids collision with existing names', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      final allocated = mod.allocateSignalName('en');
      expect(allocated, isNot(equals('en')),
          reason: 'Should not collide with existing port name');
      expect(allocated, contains('en'),
          reason: 'Should be based on the requested name');
    });

    test('successive allocations are unique', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      final a = mod.allocateSignalName('wire');
      final b = mod.allocateSignalName('wire');
      expect(a, isNot(equals(b)), reason: 'Each allocation should be unique');
    });
  });

  group('sparse storage', () {
    test('identity names not stored in renames', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(mod.signalName(mod.input('a')), equals('a'));
      expect(mod.input('a').name, equals('a'));
    });
  });

  group('determinism', () {
    test('same module produces identical canonical names', () async {
      Future<Map<String, String>> buildAndGetNames() async {
        final mod = _Counter(Logic(), Logic());
        await mod.build();
        return {
          for (final sig in mod.signals) sig.name: mod.signalName(sig),
        };
      }

      final names1 = await buildAndGetNames();
      await Simulator.reset();
      final names2 = await buildAndGetNames();

      expect(names1, equals(names2));
    });
  });

  group('filter_bank hierarchy', () {
    test('submodule canonical names work independently', () async {
      const dataWidth = 16;
      const numTaps = 3;
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final start = Logic(name: 'start');
      final samplesIn = LogicArray([2], dataWidth, name: 'samplesIn');
      final validIn = Logic(name: 'validIn');
      final inputDone = Logic(name: 'inputDone');

      final dut = FilterBank(
        clk,
        reset,
        start,
        samplesIn,
        validIn,
        inputDone,
        numTaps: numTaps,
        dataWidth: dataWidth,
        coefficients: [
          [1, 2, 1],
          [1, -2, 1],
        ],
      );
      await dut.build();

      expect(dut.signalName(dut.input('clk')), equals('clk'));
      expect(dut.signalName(dut.output('done')), equals('done'));

      for (final sub in dut.subModules) {
        for (final entry in sub.inputs.entries) {
          final name = sub.signalName(entry.value);
          expect(name, isNotEmpty);
        }
      }
    });
  });
}
