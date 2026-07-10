// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_query_test.dart
// Tests for PrefixQuery and RegexQuery matching logic.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Build a test hierarchy:
///
/// ```text
/// SoC
/// ├─ signals: [clk, reset, irq0, irq1]
/// ├─ cpu0
/// │  ├─ signals: [clk, reset, pc]
/// │  ├─ alu
/// │  │  └─ signals: [a, b, result, carry_out, overflow]
/// │  ├─ regfile
/// │  │  └─ signals: [clk, reset, d0, d1, d2, d15, wr_en]
/// │  └─ decoder
/// │     └─ signals: [opcode, enable, mode]
/// ├─ cpu1
/// │  ├─ signals: [clk, reset, pc]
/// │  ├─ alu
/// │  │  └─ signals: [a, b, result, carry_out, overflow]
/// │  └─ regfile
/// │     └─ signals: [clk, reset, d0, d1, d2, d15, wr_en]
/// ├─ mem_ctrl
/// │  ├─ signals: [clk, reset, addr, data_in, data_out, valid]
/// │  ├─ ch0
/// │  │  └─ signals: [clk, addr, data, hit, miss]
/// │  ├─ ch1
/// │  │  └─ signals: [clk, addr, data, hit, miss]
/// │  └─ ch2
/// │     └─ signals: [clk, addr, data, hit, miss]
/// └─ io_mux
///    ├─ signals: [clk, sel, data_muxed, valid_muxed]
///    ├─ uart0
///    │  └─ signals: [clk, tx, rx, baud_sel]
///    └─ uart1
///       └─ signals: [clk, tx, rx, baud_sel]
/// ```
HierarchyService buildTestHierarchy() {
  HierarchyOccurrence mkAlu() => HierarchyOccurrence(
        name: 'alu',
        definition: 'ALU',
        signals: [
          SignalOccurrence(name: 'a', width: 8),
          SignalOccurrence(name: 'b', width: 8),
          SignalOccurrence(name: 'result', width: 8),
          SignalOccurrence(name: 'carry_out', width: 1),
          SignalOccurrence(name: 'overflow', width: 1),
        ],
      );

  HierarchyOccurrence mkRegfile() => HierarchyOccurrence(
        name: 'regfile',
        definition: 'RegFile',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'reset', width: 1),
          SignalOccurrence(name: 'd0', width: 8),
          SignalOccurrence(name: 'd1', width: 8),
          SignalOccurrence(name: 'd2', width: 8),
          SignalOccurrence(name: 'd15', width: 8),
          SignalOccurrence(name: 'wr_en', width: 1),
        ],
      );

  final decoder = HierarchyOccurrence(
    name: 'decoder',
    definition: 'Decoder',
    signals: [
      SignalOccurrence(name: 'opcode', width: 4),
      SignalOccurrence(name: 'enable', width: 1),
      SignalOccurrence(name: 'mode', width: 2),
    ],
  );

  final cpu0 = HierarchyOccurrence(
    name: 'cpu0',
    definition: 'CPU',
    children: [mkAlu(), mkRegfile(), decoder],
    signals: [
      SignalOccurrence(name: 'clk', width: 1),
      SignalOccurrence(name: 'reset', width: 1),
      SignalOccurrence(name: 'pc', width: 32),
    ],
  );

  final cpu1 = HierarchyOccurrence(
    name: 'cpu1',
    definition: 'CPU',
    children: [mkAlu(), mkRegfile()],
    signals: [
      SignalOccurrence(name: 'clk', width: 1),
      SignalOccurrence(name: 'reset', width: 1),
      SignalOccurrence(name: 'pc', width: 32),
    ],
  );

  HierarchyOccurrence mkCacheChannel(String name) => HierarchyOccurrence(
        name: name,
        definition: 'CacheChannel',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'addr', width: 16),
          SignalOccurrence(name: 'data', width: 32),
          SignalOccurrence(name: 'hit', width: 1),
          SignalOccurrence(name: 'miss', width: 1),
        ],
      );

  final memCtrl = HierarchyOccurrence(
    name: 'mem_ctrl',
    definition: 'MemController',
    children: [
      mkCacheChannel('ch0'),
      mkCacheChannel('ch1'),
      mkCacheChannel('ch2')
    ],
    signals: [
      SignalOccurrence(name: 'clk', width: 1),
      SignalOccurrence(name: 'reset', width: 1),
      SignalOccurrence(name: 'addr', width: 16),
      SignalOccurrence(name: 'data_in', width: 32),
      SignalOccurrence(name: 'data_out', width: 32),
      SignalOccurrence(name: 'valid', width: 1),
    ],
  );

  HierarchyOccurrence mkUart(String name) => HierarchyOccurrence(
        name: name,
        definition: 'UART',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'tx', width: 1),
          SignalOccurrence(name: 'rx', width: 1),
          SignalOccurrence(name: 'baud_sel', width: 3),
        ],
      );

  final ioMux = HierarchyOccurrence(
    name: 'io_mux',
    definition: 'IOMux',
    children: [mkUart('uart0'), mkUart('uart1')],
    signals: [
      SignalOccurrence(name: 'clk', width: 1),
      SignalOccurrence(name: 'sel', width: 2),
      SignalOccurrence(name: 'data_muxed', width: 8),
      SignalOccurrence(name: 'valid_muxed', width: 1),
    ],
  );

  final root = HierarchyOccurrence(
    name: 'SoC',
    definition: 'SoC',
    children: [cpu0, cpu1, memCtrl, ioMux],
    signals: [
      SignalOccurrence(name: 'clk', width: 1),
      SignalOccurrence(name: 'reset', width: 1),
      SignalOccurrence(name: 'irq0', width: 1),
      SignalOccurrence(name: 'irq1', width: 1),
    ],
  );

  return BaseHierarchyAdapter.fromTree(root);
}

void main() {
  late HierarchyService svc;

  setUpAll(() {
    svc = buildTestHierarchy();
  });

  // ═══════════════════════════════════════════════════════════════
  // PrefixQuery
  // ═══════════════════════════════════════════════════════════════

  group('PrefixQuery', () {
    group('matchOccurrence', () {
      test('matches occurrence name containing segment', () {
        final q = PrefixQuery('cpu');
        // 'cpu0' contains 'cpu'
        expect(q.matchOccurrence('cpu0', 0), equals({1}));
      });

      test('returns empty set when no match', () {
        final q = PrefixQuery('mem');
        expect(q.matchOccurrence('cpu0', 0), isEmpty);
      });

      test('past end of segments returns current state', () {
        final q = PrefixQuery('cpu');
        // stateIndex == segmentCount → already consumed
        expect(q.matchOccurrence('anything', 1), equals({1}));
      });

      test('multi-segment: advances one segment at a time', () {
        final q = PrefixQuery('cpu/alu');
        expect(q.matchOccurrence('cpu0', 0), equals({1}));
        expect(q.matchOccurrence('alu', 1), equals({2}));
        // 'regfile' doesn't match 'alu'
        expect(q.matchOccurrence('regfile', 1), isEmpty);
      });

      test('dot separator treated as slash', () {
        final q = PrefixQuery('cpu.alu');
        expect(q.segmentCount, equals(2));
        expect(q.matchOccurrence('cpu0', 0), equals({1}));
      });
    });

    group('matchSignal', () {
      test('matches signal name with startsWith', () {
        final q = PrefixQuery('cpu/clk');
        // At state 1 (after matching 'cpu'), 'clk' starts with 'clk'
        expect(q.matchSignal('clk', 1), isTrue);
        expect(q.matchSignal('clk_gated', 1), isTrue);
      });

      test('does not match signal for non-last segment', () {
        final q = PrefixQuery('cpu/alu/res');
        // At state 1, there are still 2 segments left → only last matches
        expect(q.matchSignal('result', 1), isFalse);
        // At state 2, this is the last segment
        expect(q.matchSignal('result', 2), isTrue);
      });

      test('past end matches any signal', () {
        final q = PrefixQuery('cpu');
        expect(q.matchSignal('anything', 1), isTrue);
      });
    });

    group('isComplete', () {
      test('complete when stateIndex >= segmentCount', () {
        final q = PrefixQuery('cpu/alu');
        expect(q.isComplete(0), isFalse);
        expect(q.isComplete(1), isFalse);
        expect(q.isComplete(2), isTrue);
        expect(q.isComplete(3), isTrue);
      });
    });

    group('isEmpty', () {
      test('empty for blank query', () {
        expect(PrefixQuery('').isEmpty, isTrue);
        expect(PrefixQuery('  ').isEmpty, isTrue);
      });

      test('not empty for real query', () {
        expect(PrefixQuery('clk').isEmpty, isFalse);
      });
    });

    group('target property', () {
      test('defaults to signals', () {
        expect(PrefixQuery('x').target, equals(SearchTarget.signals));
      });

      test('can be set to occurrences', () {
        final q = PrefixQuery('x', target: SearchTarget.occurrences);
        expect(q.target, equals(SearchTarget.occurrences));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // RegexQuery
  // ═══════════════════════════════════════════════════════════════

  group('RegexQuery', () {
    group('exact name matching', () {
      test('matches exact occurrence name', () {
        final q = RegexQuery('SoC/cpu0/alu');
        expect(q.matchOccurrence('SoC', 0), equals({1}));
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
        expect(q.matchOccurrence('alu', 2), equals({3}));
      });

      test('does not match wrong name', () {
        final q = RegexQuery('SoC/cpu0');
        expect(q.matchOccurrence('cpu1', 1), isEmpty);
      });

      test('case sensitive', () {
        final q = RegexQuery('SoC/cpu0');
        expect(q.matchOccurrence('SoC', 0), equals({1}));
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
      });
    });

    group('glob wildcard *', () {
      test('star matches any characters', () {
        final q = RegexQuery('SoC/cpu*');
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
        expect(q.matchOccurrence('cpu1', 1), equals({2}));
        expect(q.matchOccurrence('mem_ctrl', 1), isEmpty);
      });

      test('star at start', () {
        final q = RegexQuery('SoC/*_ctrl');
        expect(q.matchOccurrence('mem_ctrl', 1), equals({2}));
        expect(q.matchOccurrence('cpu0', 1), isEmpty);
      });

      test('star in middle', () {
        final q = RegexQuery('SoC/io_*');
        expect(q.matchOccurrence('io_mux', 1), equals({2}));
        expect(q.matchOccurrence('io_ctrl', 1), equals({2}));
        expect(q.matchOccurrence('cpu0', 1), isEmpty);
      });

      test('standalone star matches anything', () {
        final q = RegexQuery('SoC/*');
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
        expect(q.matchOccurrence('mem_ctrl', 1), equals({2}));
        expect(q.matchOccurrence('io_mux', 1), equals({2}));
      });
    });

    group('glob wildcard ?', () {
      test('question mark matches one character', () {
        final q = RegexQuery('SoC/cpu?');
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
        expect(q.matchOccurrence('cpu1', 1), equals({2}));
        // 'cpuXY' is two chars after 'cpu' → no match
        expect(q.matchOccurrence('cpuXY', 1), isEmpty);
      });
    });

    group('glob-star ** (cross hierarchy boundaries)', () {
      test('** matches zero levels', () {
        final q = RegexQuery('SoC/**/alu');
        // ** at index 1 can match zero levels → try index 2 ('alu')
        // directly against children of SoC
        final states = q.matchOccurrence('alu', 1);
        // Should include state 1 (stay at **) and possibly skip to 2
        expect(states, contains(1));
      });

      test('** matches one or more levels', () {
        final q = RegexQuery('SoC/**/clk');
        // ** stays at ** when consuming a node
        expect(q.matchOccurrence('cpu0', 1), contains(1));
        expect(q.matchOccurrence('alu', 1), contains(1));
      });

      test('** followed by exact segment', () {
        final q = RegexQuery('SoC/**/alu');
        // At state 1 (**), 'alu' should match both staying and advancing
        final states = q.matchOccurrence('alu', 1);
        expect(states, contains(1)); // stay at **
        expect(states, contains(3)); // skip ** + match 'alu' → index 3
      });

      test('isComplete with trailing **', () {
        final q = RegexQuery('SoC/**');
        expect(q.isComplete(1), isTrue); // ** can match zero
        expect(q.isComplete(2), isTrue); // past end
      });
    });

    group('character classes [...]', () {
      test('matches character range', () {
        final q = RegexQuery('SoC/**/d[0-9]+');
        // Signal matching
        expect(q.matchSignal('d0', 2), isTrue);
        expect(q.matchSignal('d1', 2), isTrue);
        expect(q.matchSignal('d15', 2), isTrue);
        expect(q.matchSignal('clk', 2), isFalse);
      });

      test('fixed character set', () {
        final q = RegexQuery('SoC/mem_ctrl/ch[012]');
        expect(q.matchOccurrence('ch0', 2), equals({3}));
        expect(q.matchOccurrence('ch1', 2), equals({3}));
        expect(q.matchOccurrence('ch2', 2), equals({3}));
        expect(q.matchOccurrence('ch3', 2), isEmpty);
      });
    });

    group('alternation (...|...)', () {
      test('matches either alternative', () {
        final q = RegexQuery('SoC/**/(clk|reset)');
        expect(q.matchSignal('clk', 2), isTrue);
        expect(q.matchSignal('reset', 2), isTrue);
        expect(q.matchSignal('data', 2), isFalse);
      });

      test('alternation on occurrences', () {
        final q = RegexQuery('SoC/(cpu0|cpu1)');
        expect(q.matchOccurrence('cpu0', 1), equals({2}));
        expect(q.matchOccurrence('cpu1', 1), equals({2}));
        expect(q.matchOccurrence('mem_ctrl', 1), isEmpty);
      });
    });

    group('regex quantifiers', () {
      test('{n,m} repetition', () {
        final q = RegexQuery('SoC/**/d[0-9]{1,2}');
        expect(q.matchSignal('d0', 2), isTrue);
        expect(q.matchSignal('d15', 2), isTrue);
        // 'd123' has 3 digits → no match (anchored)
        expect(q.matchSignal('d123', 2), isFalse);
      });

      test('+ one or more', () {
        final q = RegexQuery('SoC/**/irq[0-9]+');
        expect(q.matchSignal('irq0', 2), isTrue);
        expect(q.matchSignal('irq1', 2), isTrue);
        expect(q.matchSignal('irq', 2), isFalse);
      });
    });

    group('matchSignal', () {
      test('exact signal name', () {
        final q = RegexQuery('SoC/cpu0/clk');
        expect(q.matchSignal('clk', 2), isTrue);
        expect(q.matchSignal('reset', 2), isFalse);
      });

      test('glob * on signal', () {
        final q = RegexQuery('SoC/cpu0/alu/*');
        expect(q.matchSignal('a', 3), isTrue);
        expect(q.matchSignal('result', 3), isTrue);
      });

      test('glob * prefix on signal', () {
        final q = RegexQuery('SoC/**/carry_*');
        expect(q.matchSignal('carry_out', 2), isTrue);
        expect(q.matchSignal('overflow', 2), isFalse);
      });

      test('** then signal matches all signals when past segments', () {
        final q = RegexQuery('SoC/**');
        // At state 1 (**), isComplete is true → match all signals
        expect(q.matchSignal('clk', 1), isTrue);
        expect(q.matchSignal('anything', 1), isTrue);
      });

      test('signal does not match non-terminal segment', () {
        // SoC/cpu0/alu/result — 'result' is segment index 3, last segment
        final q = RegexQuery('SoC/cpu0/alu/result');
        // At state 2, there's still 'result' to match → not last-terminal
        expect(q.matchSignal('result', 2), isFalse);
        // At state 3 it is the last segment
        expect(q.matchSignal('result', 3), isTrue);
      });
    });

    group('isComplete', () {
      test('complete when past all segments', () {
        final q = RegexQuery('SoC/cpu0');
        expect(q.isComplete(0), isFalse);
        expect(q.isComplete(1), isFalse);
        expect(q.isComplete(2), isTrue);
      });

      test('complete with trailing glob-stars', () {
        final q = RegexQuery('SoC/**');
        expect(q.isComplete(0), isFalse);
        expect(q.isComplete(1), isTrue); // ** matches zero
      });

      test('not complete with remaining regex segments', () {
        final q = RegexQuery('SoC/**/alu');
        expect(q.isComplete(1), isFalse); // ** then 'alu' remains
      });
    });

    group('target property', () {
      test('defaults to signals', () {
        expect(RegexQuery('x').target, equals(SearchTarget.signals));
      });

      test('can be set to both', () {
        final q = RegexQuery('x', target: SearchTarget.both);
        expect(q.target, equals(SearchTarget.both));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Factory constructors on HierarchyQuery
  // ═══════════════════════════════════════════════════════════════

  group('HierarchyQuery factories', () {
    test('.prefix creates PrefixQuery', () {
      final q = HierarchyQuery.prefix('cpu/clk');
      expect(q, isA<PrefixQuery>());
      expect(q.segmentCount, equals(2));
    });

    test('.regex creates RegexQuery', () {
      final q = HierarchyQuery.regex('SoC/**/clk');
      expect(q, isA<RegexQuery>());
      expect(q.segmentCount, equals(3));
    });

    test('.prefix with target', () {
      final q = HierarchyQuery.prefix('x', target: SearchTarget.occurrences);
      expect(q.target, equals(SearchTarget.occurrences));
    });

    test('.regex with target', () {
      final q = HierarchyQuery.regex('x', target: SearchTarget.both);
      expect(q.target, equals(SearchTarget.both));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Edge cases
  // ═══════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('empty query is isEmpty', () {
      expect(HierarchyQuery.prefix('').isEmpty, isTrue);
      expect(HierarchyQuery.regex('').isEmpty, isTrue);
      expect(HierarchyQuery.prefix('  ').isEmpty, isTrue);
      expect(HierarchyQuery.regex('  ').isEmpty, isTrue);
    });

    test('PrefixQuery with only separators', () {
      final q = PrefixQuery('///');
      expect(q.segmentCount, equals(0));
      expect(q.isEmpty, isFalse); // raw string isn't blank
      expect(q.isComplete(0), isTrue); // no segments to match
    });

    test('RegexQuery single segment', () {
      final q = RegexQuery('clk');
      expect(q.segmentCount, equals(1));
      expect(q.matchSignal('clk', 0), isTrue);
      expect(q.matchSignal('reset', 0), isFalse);
    });

    test('RegexQuery multiple consecutive glob-stars', () {
      final q = RegexQuery('SoC/**/**/clk');
      // Should still work — multiple **'s just redundantly match zero+
      expect(q.isComplete(1), isFalse); // **/** then clk
      final states = q.matchOccurrence('cpu0', 1);
      expect(states, contains(1)); // stay at first **
    });

    test('RegexQuery with .* explicit regex', () {
      final q = RegexQuery('SoC/**/.*mux.*');
      expect(q.matchOccurrence('io_mux', 2), equals({3}));
      expect(q.matchSignal('data_muxed', 2), isTrue);
      expect(q.matchSignal('valid_muxed', 2), isTrue);
      expect(q.matchSignal('clk', 2), isFalse);
    });

    test('PrefixQuery crossesBoundaries is false', () {
      expect(PrefixQuery('x').crossesBoundaries, isFalse);
    });

    test('RegexQuery crossesBoundaries is false (uses ** explicitly)', () {
      expect(RegexQuery('SoC/**/clk').crossesBoundaries, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Integration: queries against the real hierarchy via
  // HierarchyService (to verify the contract makes sense)
  // ═══════════════════════════════════════════════════════════════

  group('Integration with hierarchy (signal path search)', () {
    test('PrefixQuery segments match existing search', () {
      // Verify PrefixQuery produces the same segments as
      // the existing searchSignalPaths logic.
      final q = PrefixQuery('cpu/alu/res');
      final paths = svc.searchSignalPaths('cpu/alu/res');
      // Both cpu0 and cpu1 have ALU with 'result'
      expect(paths.length, equals(2));
      for (final p in paths) {
        expect(p, contains('result'));
      }
      // Verify the query matches the same way
      expect(q.matchOccurrence('cpu0', 0), isNotEmpty);
      expect(q.matchOccurrence('alu', 1), isNotEmpty);
      expect(q.matchSignal('result', 2), isTrue);
    });

    test('RegexQuery glob matches existing regex search', () {
      // SoC/**/clk should find clk at many levels
      final paths = svc.searchSignalPathsRegex('SoC/**/clk');
      // clk exists at: SoC, cpu0, cpu1, cpu0/regfile, cpu1/regfile,
      // mem_ctrl, ch0, ch1, ch2, io_mux, uart0, uart1 = 12 total
      expect(paths.length, equals(12));
      for (final p in paths) {
        expect(p, endsWith('/clk'));
      }
    });

    test('RegexQuery character class matches indexed signals', () {
      final paths = svc.searchSignalPathsRegex('SoC/**/d[0-9]+');
      // d0, d1, d2, d15 in cpu0/regfile and cpu1/regfile = 8 total
      expect(paths.length, equals(8));
      for (final p in paths) {
        expect(p, matches(RegExp(r'/d\d+$')));
      }
    });

    test('RegexQuery alternation matches specific signals', () {
      final paths = svc.searchSignalPathsRegex('SoC/**/(tx|rx)');
      // tx and rx in uart0 and uart1 = 4 total
      expect(paths.length, equals(4));
    });

    test('RegexQuery ch[0-2] matches channel occurrences', () {
      final paths = svc.searchOccurrencePathsRegex('SoC/mem_ctrl/ch[0-2]');
      expect(paths.length, equals(3));
      expect(
          paths,
          containsAll([
            'SoC/mem_ctrl/ch0',
            'SoC/mem_ctrl/ch1',
            'SoC/mem_ctrl/ch2',
          ]));
    });

    test('RegexQuery *_mux matches occurrence by suffix', () {
      final paths = svc.searchOccurrencePathsRegex('SoC/*_mux');
      expect(paths.length, equals(1));
      expect(paths.first, equals('SoC/io_mux'));
    });

    test('RegexQuery .*mux.* matches signals containing mux', () {
      final paths = svc.searchSignalPathsRegex('SoC/**/.*mux.*');
      expect(paths, contains('SoC/io_mux/data_muxed'));
      expect(paths, contains('SoC/io_mux/valid_muxed'));
    });

    test('PrefixQuery finds irq signals at root', () {
      final paths = svc.searchSignalPaths('SoC/irq');
      expect(paths.length, equals(2));
      expect(paths, contains('SoC/irq0'));
      expect(paths, contains('SoC/irq1'));
    });

    test('RegexQuery baud_sel across both UARTs', () {
      final paths = svc.searchSignalPathsRegex('SoC/**/baud_sel');
      expect(paths.length, equals(2));
      expect(paths, contains('SoC/io_mux/uart0/baud_sel'));
      expect(paths, contains('SoC/io_mux/uart1/baud_sel'));
    });
  });
}
