// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_simcompare_test.dart
// Tests for SystemC synthesis and simulation comparison.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// A simple module with basic gates for testing SystemC synthesis.
class GateModule extends Module {
  GateModule(Logic a, Logic b) : super(name: 'GateModule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final aAndB = addOutput('a_and_b');
    final aOrB = addOutput('a_or_b');
    final notA = addOutput('not_a');

    aAndB <= a & b;
    aOrB <= a | b;
    notA <= ~a;
  }
}

/// A simple counter for testing sequential SystemC synthesis.
class SimpleCounter extends Module {
  SimpleCounter(Logic clk, Logic reset, Logic en) : super(name: 'Counter') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    en = addInput('en', en);
    final val = addOutput('val', width: 8);

    final nextVal = Logic(name: 'nextVal', width: 8);

    Sequential(clk, reset: reset, [
      If(en, then: [nextVal < nextVal + 1], orElse: [nextVal < nextVal]),
    ]);

    val <= nextVal;
  }
}

/// A flip-flop module for testing.
class FlopModule extends Module {
  FlopModule(Logic clk, Logic reset, Logic d) : super(name: 'FlopModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    d = addInput('d', d, width: 8);
    final q = addOutput('q', width: 8);
    q <= flop(clk, d, reset: reset);
  }
}

/// A flip-flop with enable.
class FlopEnModule extends Module {
  FlopEnModule(Logic clk, Logic reset, Logic en, Logic d)
      : super(name: 'FlopEnModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    en = addInput('en', en);
    d = addInput('d', d, width: 8);
    final q = addOutput('q', width: 8);
    q <= flop(clk, d, reset: reset, en: en);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('SimCompare SystemC', () {
    test('gate module passes vectors', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = GateModule(a, b);
      await mod.build();

      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0, 'a_or_b': 0, 'not_a': 1}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0, 'a_or_b': 1, 'not_a': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0, 'a_or_b': 1, 'not_a': 1}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1, 'a_or_b': 1, 'not_a': 0}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('counter module passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final mod = SimpleCounter(clk, reset, en);
      await mod.build();

      // Same vectors as counter_test.dart (iverilog-compatible timing)
      final vectors = [
        Vector({'en': 0, 'reset': 0}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];

      SimCompare.checkSystemCVector(mod, vectors, dontDeleteTmpFiles: true);
    });

    test('flip-flop module passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final d = Logic(name: 'd', width: 8);
      final mod = FlopModule(clk, reset, d);
      await mod.build();

      // Flop: output follows input with 1-cycle latency
      final vectors = [
        Vector({'d': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0xAA, 'reset': 0}, {'q': 0}),
        Vector({'d': 0xBB, 'reset': 0}, {'q': 0xAA}),
        Vector({'d': 0xCC, 'reset': 0}, {'q': 0xBB}),
        Vector({'d': 0xDD, 'reset': 0}, {'q': 0xCC}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('flip-flop with enable passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final d = Logic(name: 'd', width: 8);
      final mod = FlopEnModule(clk, reset, en, d);
      await mod.build();

      // When en=0, q holds; when en=1, q follows d with 1-cycle latency
      final vectors = [
        Vector({'d': 0, 'en': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0, 'en': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0x42, 'en': 1, 'reset': 0}, {'q': 0}),
        Vector({'d': 0x55, 'en': 1, 'reset': 0}, {'q': 0x42}),
        Vector({'d': 0xFF, 'en': 0, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0x00, 'en': 0, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0x99, 'en': 1, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0xAA, 'en': 1, 'reset': 0}, {'q': 0x99}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('counter trace-based comparison', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final mod = SimpleCounter(clk, reset, en);
      await mod.build();

      // Use the trace-based approach: just write normal simulation code,
      // no vectors needed. The method records all I/O at every clock edge
      // and replays through SystemC.
      final result = await SimCompare.systemcSimCompare(
        mod,
        clk,
        stimulus: () async {
          reset.inject(1);
          en.inject(0);
          Simulator.registerAction(25, () {
            reset.put(0);
            en.put(1);
          });
          Simulator.registerAction(65, () {
            en.put(0);
          });
          Simulator.registerAction(85, () {
            en.put(1);
          });
          Simulator.setMaxSimTime(120);
        },
        dontDeleteTmpFiles: true,
      );
      expect(result, isTrue);
    });
  });
}
