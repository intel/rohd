// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_registry_test.dart
// Tests for Module canonical naming (Namer).
//
// 2026 April 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';
import 'package:test/test.dart';

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
    Sequential.multi(
      [SimpleClockGenerator(10).clk, reset],
      [
        If(
          reset,
          then: [val < 0],
          orElse: [
            If(en, then: [val < nextVal]),
          ],
        ),
      ],
    );
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

      expect(mod.namer.signalNameOfBest([mod.input('a')]), equals('a'));
      expect(mod.namer.signalNameOfBest([mod.input('b')]), equals('b'));
      expect(
        mod.namer.signalNameOfBest([mod.output('a_bar')]),
        equals('a_bar'),
      );
      expect(
        mod.namer.signalNameOfBest([mod.output('a_and_b')]),
        equals('a_and_b'),
      );
    });

    test('returns internal signal names', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      expect(mod.namer.signalNameOfBest([mod.input('en')]), equals('en'));
      expect(mod.namer.signalNameOfBest([mod.input('reset')]), equals('reset'));
      expect(mod.namer.signalNameOfBest([mod.output('val')]), equals('val'));
    });

    test('agrees with signalNameOfBest after synth', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      for (final entry in mod.inputs.entries) {
        expect(
          mod.namer.signalNameOfBest([entry.value]),
          isNotNull,
          reason: 'signalNameOfBest should work for input ${entry.key}',
        );
      }
      for (final entry in mod.outputs.entries) {
        expect(
          mod.namer.signalNameOfBest([entry.value]),
          isNotNull,
          reason: 'signalNameOfBest should work for output ${entry.key}',
        );
      }
    });
  });

  group('single-signal allocation', () {
    test('avoids collision with existing names', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      final sig = Logic(name: 'en', naming: Naming.renameable);
      final allocated = mod.namer.signalNameOfBest([sig]);
      expect(
        allocated,
        isNot(equals('en')),
        reason: 'Should not collide with existing port name',
      );
      expect(
        allocated,
        contains('en'),
        reason: 'Should be based on the requested name',
      );
    });

    test('successive allocations are unique', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      final a = mod.namer.signalNameOfBest([
        Logic(name: 'wire', naming: Naming.renameable),
      ]);
      final b = mod.namer.signalNameOfBest([
        Logic(name: 'wire', naming: Naming.renameable),
      ]);
      expect(a, isNot(equals(b)), reason: 'Each allocation should be unique');
    });
  });

  group('sparse storage', () {
    test('identity names not stored in renames', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(mod.namer.signalNameOfBest([mod.input('a')]), equals('a'));
      expect(mod.input('a').name, equals('a'));
    });
  });

  group('determinism', () {
    test('same module produces identical canonical names', () async {
      Future<Map<String, String>> buildAndGetNames() async {
        final mod = _Counter(Logic(), Logic());
        await mod.build();
        return {
          for (final sig in mod.signals)
            sig.name: mod.namer.signalNameOfBest([sig]),
        };
      }

      final names1 = await buildAndGetNames();
      await Simulator.reset();
      final names2 = await buildAndGetNames();

      expect(names1, equals(names2));
    });
  });

  group('isAvailable', () {
    test('port names are not available', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(mod.namer.isAvailable('a'), isFalse);
      expect(mod.namer.isAvailable('b'), isFalse);
      expect(mod.namer.isAvailable('a_bar'), isFalse);
      expect(mod.namer.isAvailable('a_and_b'), isFalse);
    });

    test('unallocated names are available', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(mod.namer.isAvailable('xyz'), isTrue);
      expect(mod.namer.isAvailable('new_signal'), isTrue);
    });

    test('allocated names become unavailable', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final name = mod.namer.signalNameOfBest([
        Logic(name: 'wire', naming: Naming.renameable),
      ]);
      expect(mod.namer.isAvailable(name), isFalse);
    });
  });

  group('reserved single-signal allocation', () {
    test('reserved signal claims exact name', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final sig = Logic(name: 'my_wire', naming: Naming.reserved);
      final name = mod.namer.signalNameOfBest([sig]);
      expect(name, equals('my_wire'));
      expect(mod.namer.isAvailable('my_wire'), isFalse);
    });

    test('reserved collision throws', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(
        () => mod.namer.signalNameOfBest([
          Logic(name: 'a', naming: Naming.reserved),
        ]),
        throwsException,
      );
    });
  });

  group('baseName', () {
    test('reserved signal uses name directly', () {
      final sig = Logic(name: 'myReserved', naming: Naming.reserved);
      expect(Namer.baseName(sig), equals('myReserved'));
    });

    test('renameable signal uses sanitized structureName', () {
      final sig = Logic(name: 'mySignal', naming: Naming.renameable);
      // structureName for a top-level signal equals its name
      expect(Namer.baseName(sig), contains('mySignal'));
    });

    test('unpreferred name detected', () {
      expect(Naming.isUnpreferred('_hidden'), isTrue);
      expect(Naming.isUnpreferred('visible'), isFalse);
    });
  });

  group('signalNameOfBest', () {
    test('const value returns value string', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final c = Const(LogicValue.ofString('01'));
      final sig = Logic(name: 'x');
      final name = mod.namer.signalNameOfBest([sig], constValue: c);
      expect(name, equals(c.value.toString()));
    });

    test('constNameDisallowed falls through to candidates', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final c = Const(LogicValue.ofString('01'));
      final sig = Logic(name: 'fallback', naming: Naming.renameable);
      final name = mod.namer.signalNameOfBest(
        [sig],
        constValue: c,
        constNameDisallowed: true,
      );
      expect(name, isNot(equals(c.value.toString())));
      expect(name, contains('fallback'));
    });

    test('port wins over other candidates', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final port = mod.input('a'); // this module's port
      final reserved = Logic(name: 'res', naming: Naming.reserved);
      final name = mod.namer.signalNameOfBest([reserved, port]);
      expect(name, equals('a'));
    });

    test('reserved wins over mergeable', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final reserved = Logic(name: 'special', naming: Naming.reserved);
      final mergeable = Logic(name: 'other', naming: Naming.mergeable);
      final name = mod.namer.signalNameOfBest([mergeable, reserved]);
      expect(name, equals('special'));
    });

    test('renameable wins over mergeable', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final renameable = Logic(name: 'ren', naming: Naming.renameable);
      final mergeable = Logic(name: 'mrg', naming: Naming.mergeable);
      final name = mod.namer.signalNameOfBest([mergeable, renameable]);
      expect(name, contains('ren'));
    });

    test('preferred mergeable wins over unpreferred', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final preferred = Logic(name: 'good', naming: Naming.mergeable);
      final unpreferred = Logic(
        name: Naming.unpreferredName('bad'),
        naming: Naming.mergeable,
      );
      final name = mod.namer.signalNameOfBest([unpreferred, preferred]);
      expect(name, contains('good'));
    });

    test('caches name for all candidates', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final s1 = Logic(name: 'winner', naming: Naming.renameable);
      final s2 = Logic(name: 'loser', naming: Naming.mergeable);
      final name = mod.namer.signalNameOfBest([s1, s2]);

      // Both should resolve to the same cached name
      expect(mod.namer.signalNameOfBest([s1]), equals(name));
      expect(mod.namer.signalNameOfBest([s2]), equals(name));
    });

    test('empty candidates throws', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      expect(() => mod.namer.signalNameOfBest([]), throwsA(isA<StateError>()));
    });

    test('unnamed signals get a name', () async {
      final mod = _GateMod(Logic(), Logic());
      await mod.build();

      final unnamed = Logic(naming: Naming.unnamed);
      final name = mod.namer.signalNameOfBest([unnamed]);
      expect(name, isNotEmpty);
    });
  });
}
