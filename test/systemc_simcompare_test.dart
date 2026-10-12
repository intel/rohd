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

/// Flops and Sequential blocks sharing signals but using different reset modes.
class MixedResetModesModule extends Module {
  MixedResetModesModule(Logic clk, Logic reset, Logic d)
      : super(name: 'MixedResetModesModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    d = addInput('d', d, width: 8);

    addOutput('syncQ', width: 8) <= flop(clk, d, reset: reset);
    addOutput('asyncQ', width: 8) <=
        flop(clk, d, reset: reset, asyncReset: true);

    final syncSequential = Logic(width: 8);
    final asyncSequential = Logic(width: 8);
    Sequential(clk, reset: reset, [
      syncSequential < d,
    ]);
    Sequential(clk, reset: reset, asyncReset: true, [
      asyncSequential < d,
    ]);
    addOutput('syncSequential', width: 8) <= syncSequential;
    addOutput('asyncSequential', width: 8) <= asyncSequential;
  }
}

/// A chained combinational module for checking generated sensitivity lists.
class ChainedGateModule extends Module {
  ChainedGateModule(Logic a, Logic b, Logic c)
      : super(name: 'ChainedGateModule') {
    a = addInput('a', a);
    b = addInput('b', b);
    c = addInput('c', c);
    final y = addOutput('y');

    final mid = (a & b).named('mid');
    y <= mid | c;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(SimCompare.cleanupSystemCCache);

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

      SimCompare.checkSystemCVector(mod, vectors);
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

    test('mixed reset modes remain separate compiled processes', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final d = Logic(name: 'd', width: 8);
      final mod = MixedResetModesModule(clk, reset, d);
      await mod.build();

      final vectors = [
        Vector({
          'd': 0,
          'reset': 1
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
        Vector({
          'd': 0x5a,
          'reset': 0
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
        Vector({
          'd': 0x5a,
          'reset': 0
        }, {
          'syncQ': 0x5a,
          'asyncQ': 0x5a,
          'syncSequential': 0x5a,
          'asyncSequential': 0x5a,
        }),
        // Reset is asserted after the previous rising edge. Async members
        // reset before this check; synchronous members retain their values.
        Vector({
          'd': 0x5a,
          'reset': 1
        }, {
          'syncQ': 0x5a,
          'asyncQ': 0,
          'syncSequential': 0x5a,
          'asyncSequential': 0,
        }),
        // The next rising edge resets the synchronous members.
        Vector({
          'd': 0x5a,
          'reset': 1
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('independent inline gates share a method', () async {
      final mod = GateModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final systemc = SystemCService(mod, register: false).output;
      final assignMethods =
          RegExp(r'SC_METHOD\(assign_\d+\);').allMatches(systemc).toList();

      expect(assignMethods, hasLength(1));
      expect(systemc, contains('sensitive << a;'));
      expect(systemc, contains('sensitive << b;'));
      expect(systemc, contains('a_and_b = a.read() & b.read();'));
      expect(systemc, contains('a_or_b = a.read() | b.read();'));
      expect(systemc, contains('not_a = !a.read();'));
    });

    test('chained inline gates use minimal sensitivity lists', () async {
      final mod = ChainedGateModule(
        Logic(name: 'a'),
        Logic(name: 'b'),
        Logic(name: 'c'),
      );
      await mod.build();

      final systemc = SystemCService(mod, register: false).output;
      final sensitivityBlocks = RegExp(
        r'SC_METHOD\(assign_\d+\);\n((?:    sensitive << .+;\n)+)',
      ).allMatches(systemc).map((match) => match.group(1)!).toList();

      expect(sensitivityBlocks, hasLength(2));
      expect(
        sensitivityBlocks,
        contains(
          allOf(
            contains('sensitive << a;'),
            contains('sensitive << b;'),
            isNot(contains('sensitive << mid;')),
          ),
        ),
      );
      expect(
        sensitivityBlocks,
        contains(
          allOf(
            contains('sensitive << mid;'),
            contains('sensitive << c;'),
            isNot(contains('sensitive << a;')),
            isNot(contains('sensitive << b;')),
          ),
        ),
      );
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
      );
      expect(result, isTrue);
    });
  });
}
