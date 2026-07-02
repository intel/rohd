// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_name_parity_test.dart
// Tests that verify canonicalNameOf works consistently across
// different synthesis paths (SV and netlist).
//
// 2026 April 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

import '../example/filter_bank.dart';

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

class _CollidingNames extends Module {
  late final Logic firstDup;
  late final Logic secondDup;

  _CollidingNames(Logic a, Logic b) : super(name: 'collidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');

    firstDup = Logic(name: 'dup');
    secondDup = Logic(name: 'dup');

    firstDup <= a & b;
    secondDup <= a | b;
    y <= firstDup ^ secondDup;
  }
}

class _PartiallyInlineCollidingNames extends Module {
  late final Logic inlinedDup;
  late final Logic retainedDup;

  _PartiallyInlineCollidingNames(Logic a, Logic b)
    : super(name: 'partiallyInlineCollidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');

    inlinedDup = Logic(name: 'dup');
    retainedDup = Logic(name: 'dup');

    inlinedDup <= a & b;
    retainedDup <= a | b;
    y <= inlinedDup ^ retainedDup;
    z <= retainedDup & a;
  }
}

class _CollapsedInstanceCollidingNames extends Module {
  late final Logic retainedDup;

  _CollapsedInstanceCollidingNames(Logic a, Logic b)
    : super(name: 'collapsedInstanceCollidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');

    final collapsedInstanceOut = And2Gate(a, b, name: 'dup').out;
    retainedDup = Logic(name: 'dup');

    retainedDup <= a | b;
    y <= collapsedInstanceOut ^ retainedDup;
    z <= retainedDup;
  }
}

class _ReverseInternalSignalOrderSynthModuleDefinition
    extends SynthModuleDefinition {
  _ReverseInternalSignalOrderSynthModuleDefinition(super.module);

  @override
  void process() {
    internalSignals
      ..clear()
      ..addAll(internalSignals.toList().reversed);
  }
}

Future<Map<String, String>> _collisionNamesAfter(
  Iterable<void Function(_CollidingNames)> synthesize,
) async {
  final mod = _CollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'firstDup': mod.namer.signalNameOfBest([mod.firstDup]),
    'secondDup': mod.namer.signalNameOfBest([mod.secondDup]),
  };
}

Future<Map<String, String>> _collisionNamesAfterSynthDefinition(
  SynthModuleDefinition Function(_CollidingNames) createSynthDefinition,
) async {
  final mod = _CollidingNames(Logic(), Logic());
  await mod.build();

  createSynthDefinition(mod);

  return {
    'firstDup': mod.namer.signalNameOfBest([mod.firstDup]),
    'secondDup': mod.namer.signalNameOfBest([mod.secondDup]),
  };
}

Future<Map<String, String>> _partialInlineCollisionNamesAfter(
  Iterable<void Function(_PartiallyInlineCollidingNames)> synthesize,
) async {
  final mod = _PartiallyInlineCollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'retainedDup': mod.namer.signalNameOfBest([mod.retainedDup]),
    'inlinedDup': mod.namer.signalNameOfBest([mod.inlinedDup]),
  };
}

Future<Map<String, String>> _collapsedInstanceCollisionNamesAfter(
  Iterable<void Function(_CollapsedInstanceCollidingNames)> synthesize,
) async {
  final mod = _CollapsedInstanceCollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'retainedDup': mod.namer.signalNameOfBest([mod.retainedDup]),
  };
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('canonicalNameOf after netlist synthesis', () {
    test('counter — returns names after netlist synthesis', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();
      mod.generateNetlist();

      expect(mod.namer.signalNameOfBest([mod.input('en')]), equals('en'));
      expect(mod.namer.signalNameOfBest([mod.input('reset')]), equals('reset'));
      expect(mod.namer.signalNameOfBest([mod.output('val')]), equals('val'));
    });

    test('filter_bank — returns names for sub-module signals', () async {
      const dataWidth = 16;
      const numTaps = 3;
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final start = Logic(name: 'start');
      final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
      final inputDone = Logic(name: 'inputDone');

      final dut = FilterBank(
        clk,
        reset,
        start,
        samples,
        inputDone,
        numTaps: numTaps,
        dataWidth: dataWidth,
        coefficients: [
          [1, 2, 1],
          [1, -2, 1],
        ],
      );
      await dut.build();
      dut.generateNetlist();

      expect(dut.namer.signalNameOfBest([dut.input('clk')]), equals('clk'));
      expect(dut.namer.signalNameOfBest([dut.input('reset')]), equals('reset'));
      expect(dut.namer.signalNameOfBest([dut.output('done')]), equals('done'));
    });
  });

  group('canonicalNameOf after SV synthesis', () {
    test('counter — returns canonical name after SV synth', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      mod.generateSynth();

      expect(mod.namer.signalNameOfBest([mod.input('en')]), equals('en'));
      expect(mod.namer.signalNameOfBest([mod.input('reset')]), equals('reset'));
    });
  });

  group('cross-synthesizer parity', () {
    test(
      'counter — SV and netlist produce identical canonicalNameOf',
      () async {
        final modNetlist = _Counter(Logic(), Logic());
        await modNetlist.build();
        modNetlist.generateNetlist();
        await Simulator.reset();

        final modSv = _Counter(Logic(), Logic());
        await modSv.build();
        modSv.generateSynth();

        // Both paths use the same Namer, so names must match.
        final enNetlist = modNetlist.namer.signalNameOfBest([
          modNetlist.input('en'),
        ]);
        final enSv = modSv.namer.signalNameOfBest([modSv.input('en')]);

        expect(
          enSv,
          equals(enNetlist),
          reason: 'SV and netlist should produce identical canonical names',
        );
      },
    );

    test(
      'colliding mergeable names remain stable across synthesis order',
      () async {
        void runNetlist(_CollidingNames mod) => mod.generateNetlist();
        void runSv(_CollidingNames mod) => mod.generateSynth();

        final netlistOnly = await _collisionNamesAfter([runNetlist]);
        await Simulator.reset();

        final svOnly = await _collisionNamesAfter([runSv]);
        await Simulator.reset();

        final netlistThenSv = await _collisionNamesAfter([runNetlist, runSv]);
        await Simulator.reset();

        final svThenNetlist = await _collisionNamesAfter([runSv, runNetlist]);

        expect(netlistOnly, equals(svOnly));
        expect(netlistThenSv, equals(netlistOnly));
        expect(svThenNetlist, equals(netlistOnly));

        expect(
          netlistOnly['secondDup'],
          isNot(equals(netlistOnly['firstDup'])),
        );
      },
    );

    test(
      'colliding mergeable names ignore internal signal walk order',
      () async {
        final forward = await _collisionNamesAfterSynthDefinition(
          SynthModuleDefinition.new,
        );
        await Simulator.reset();

        final reversed = await _collisionNamesAfterSynthDefinition(
          _ReverseInternalSignalOrderSynthModuleDefinition.new,
        );

        expect(reversed, equals(forward));
        expect(forward['firstDup'], equals('dup'));
        expect(forward['secondDup'], equals('dup_0'));
      },
    );

    test('colliding names stay stable when SV inlines one signal', () async {
      void runNetlist(_PartiallyInlineCollidingNames mod) =>
          mod.generateNetlist();
      void runSv(_PartiallyInlineCollidingNames mod) => mod.generateSynth();

      final netlistOnly = await _partialInlineCollisionNamesAfter([runNetlist]);
      await Simulator.reset();

      final svOnly = await _partialInlineCollisionNamesAfter([runSv]);
      await Simulator.reset();

      final netlistThenSv = await _partialInlineCollisionNamesAfter([
        runNetlist,
        runSv,
      ]);
      await Simulator.reset();

      final svThenNetlist = await _partialInlineCollisionNamesAfter([
        runSv,
        runNetlist,
      ]);

      expect(svOnly, equals(netlistOnly));
      expect(netlistThenSv, equals(netlistOnly));
      expect(svThenNetlist, equals(netlistOnly));
      expect(netlistOnly['inlinedDup'], equals('dup'));
      expect(netlistOnly['retainedDup'], equals('dup_0'));
    });

    test(
      'signal names stay stable when SV collapses a colliding instance',
      () async {
        void runNetlist(_CollapsedInstanceCollidingNames mod) =>
            mod.generateNetlist();
        void runSv(_CollapsedInstanceCollidingNames mod) => mod.generateSynth();

        final netlistOnly = await _collapsedInstanceCollisionNamesAfter([
          runNetlist,
        ]);
        await Simulator.reset();

        final svOnly = await _collapsedInstanceCollisionNamesAfter([runSv]);
        await Simulator.reset();

        final netlistThenSv = await _collapsedInstanceCollisionNamesAfter([
          runNetlist,
          runSv,
        ]);
        await Simulator.reset();

        final svThenNetlist = await _collapsedInstanceCollisionNamesAfter([
          runSv,
          runNetlist,
        ]);

        expect(svOnly, equals(netlistOnly));
        expect(netlistThenSv, equals(netlistOnly));
        expect(svThenNetlist, equals(netlistOnly));
        expect(netlistOnly['retainedDup'], equals('dup'));
      },
    );
  });
}
