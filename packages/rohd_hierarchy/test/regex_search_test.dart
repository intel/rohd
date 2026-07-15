// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// regex_search_test.dart
// Tests for regex-based hierarchy search.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('Regex search - HierarchyService', () {
    late HierarchyService hierarchy;

    setUpAll(() {
      // Build a test hierarchy:
      //
      // Top
      //   CPU
      //     ALU        signals: [a, b, result, carry_out]
      //     Decoder    signals: [opcode, enable]
      //     RegFile    signals: [clk, reset, d0, d1, d2, d15]
      //   Memory
      //     Cache      signals: [clk, addr, data, hit]
      //     DRAM       signals: [clk, cas, ras]
      //   IO
      //     UART       signals: [clk, tx, rx]
      //   signals (Top): [clk, reset]

      final alu = HierarchyOccurrence(
        name: 'ALU',
        signals: [
          SignalOccurrence(name: 'a', width: 8),
          SignalOccurrence(name: 'b', width: 8),
          SignalOccurrence(name: 'result', width: 8),
          SignalOccurrence(name: 'carry_out', width: 1),
        ],
      );

      final decoder = HierarchyOccurrence(
        name: 'Decoder',
        signals: [
          SignalOccurrence(name: 'opcode', width: 4),
          SignalOccurrence(name: 'enable', width: 1),
        ],
      );

      final regFile = HierarchyOccurrence(
        name: 'RegFile',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'reset', width: 1),
          SignalOccurrence(name: 'd0', width: 8),
          SignalOccurrence(name: 'd1', width: 8),
          SignalOccurrence(name: 'd2', width: 8),
          SignalOccurrence(name: 'd15', width: 8),
        ],
      );

      final cpu = HierarchyOccurrence(
        name: 'CPU',
        children: [alu, decoder, regFile],
      );

      final cache = HierarchyOccurrence(
        name: 'Cache',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'addr', width: 16),
          SignalOccurrence(name: 'data', width: 32),
          SignalOccurrence(name: 'hit', width: 1),
        ],
      );

      final dram = HierarchyOccurrence(
        name: 'DRAM',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'cas', width: 1),
          SignalOccurrence(name: 'ras', width: 1),
        ],
      );

      final memory = HierarchyOccurrence(
        name: 'Memory',
        children: [cache, dram],
      );

      final uart = HierarchyOccurrence(
        name: 'UART',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'tx', width: 1),
          SignalOccurrence(name: 'rx', width: 1),
        ],
      );

      final io = HierarchyOccurrence(
        name: 'IO',
        children: [uart],
      );

      final root = HierarchyOccurrence(
        name: 'Top',
        children: [cpu, memory, io],
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'reset', width: 1),
          SignalOccurrence(name: 'data_m', width: 8),
          SignalOccurrence(name: 'addr_m', width: 16),
          SignalOccurrence(name: 'flag_m', width: 1),
        ],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    // ── Exact match ──

    test('exact path matches single signal', () {
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/ALU/result');
      expect(results, contains('Top/CPU/ALU/result'));
      expect(results.length, 1);
    });

    test('dot in regex pattern is treated as regex metachar, not separator',
        () {
      // In regex mode, `.` is NOT a hierarchy separator — only `/` is.
      // `Top.CPU` is a single segment meaning "Top" + any char + "CPU".
      final results = hierarchy.searchSignalPathsRegex('Top.CPU.ALU.result');
      // No match because the hierarchy root is "Top", not "Top.CPU.ALU"
      expect(results, isEmpty);
    });

    // ── Wildcard at one level ──

    test('.* matches all signals in a module', () {
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/ALU/.*');
      expect(
          results,
          containsAll([
            'Top/CPU/ALU/a',
            'Top/CPU/ALU/b',
            'Top/CPU/ALU/result',
            'Top/CPU/ALU/carry_out',
          ]));
      expect(results.length, 4);
    });

    test('.* matches all children at a module level', () {
      final results = hierarchy.searchSignalPathsRegex('Top/.*/clk');
      // Should match CPU/RegFile/clk but not deeper (** would be needed
      // for that).  .* represents any single-level child of Top.
      // Top has children CPU, Memory, IO — none of them have clk directly
      // (Top's own signals aren't "children").  Actually let's check:
      // Top/.*/clk means: Top / (any child) / clk as signal
      // That doesn't match because clk is in deeper modules.
      // This should return empty for signals one level below Top.
      expect(results, isEmpty);
    });

    test('.* matches modules at one level for signal search', () {
      // Top/CPU/.*/clk — matches ALU, Decoder, RegFile; only RegFile has clk
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/.*/clk');
      expect(results, contains('Top/CPU/RegFile/clk'));
      expect(results.length, 1);
    });

    // ── Glob-star ** ──

    test('** matches signals at any depth', () {
      final results = hierarchy.searchSignalPathsRegex('Top/**/clk');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/clk',
            'Top/Memory/Cache/clk',
            'Top/Memory/DRAM/clk',
            'Top/IO/UART/clk',
          ]));
      // Top's own clk is also accessible through ** matching zero levels
      expect(results, contains('Top/clk'));
    });

    test('** at beginning matches everything', () {
      final results = hierarchy.searchSignalPathsRegex('**/clk');
      // All clk signals anywhere
      expect(results.length, greaterThanOrEqualTo(5));
      expect(
          results,
          containsAll([
            'Top/clk',
            'Top/CPU/RegFile/clk',
            'Top/Memory/Cache/clk',
            'Top/Memory/DRAM/clk',
            'Top/IO/UART/clk',
          ]));
    });

    test('** between levels matches across boundaries', () {
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/**/d0');
      expect(results, contains('Top/CPU/RegFile/d0'));
      expect(results.length, 1);
    });

    test('** with regex signal pattern', () {
      final results = hierarchy.searchSignalPathsRegex('Top/**/d[0-9]+');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/d0',
            'Top/CPU/RegFile/d1',
            'Top/CPU/RegFile/d2',
            'Top/CPU/RegFile/d15',
          ]));
      expect(results.length, 4);
    });

    // ── Regex character classes ──

    test('character class in signal name', () {
      final results =
          hierarchy.searchSignalPathsRegex('Top/CPU/RegFile/d[0-2]');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/d0',
            'Top/CPU/RegFile/d1',
            'Top/CPU/RegFile/d2',
          ]));
      expect(results, isNot(contains('Top/CPU/RegFile/d15')));
    });

    // ── Alternation ──

    test('alternation in signal name', () {
      final results = hierarchy.searchSignalPathsRegex('Top/**/(?:clk|reset)');
      expect(
          results,
          containsAll([
            'Top/clk',
            'Top/reset',
            'Top/CPU/RegFile/clk',
            'Top/CPU/RegFile/reset',
            'Top/Memory/Cache/clk',
            'Top/Memory/DRAM/clk',
            'Top/IO/UART/clk',
          ]));
      expect(results.length, 7);
    });

    test('alternation in module name', () {
      final results = hierarchy.searchSignalPathsRegex('Top/(CPU|IO)/.*/clk');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/clk',
            'Top/IO/UART/clk',
          ]));
    });

    // ── Module search ──

    test('searchOccurrencePathsRegex finds modules', () {
      final results = hierarchy.searchOccurrencePathsRegex('Top/CPU/.*');
      expect(
          results,
          containsAll([
            'Top/CPU/ALU',
            'Top/CPU/Decoder',
            'Top/CPU/RegFile',
          ]));
    });

    test('searchOccurrencePathsRegex with **', () {
      final results = hierarchy.searchOccurrencePathsRegex('Top/**/DRAM');
      expect(results, contains('Top/Memory/DRAM'));
    });

    // ── Enriched results ──

    test('searchSignalsRegex returns SignalSearchResult objects', () {
      final results = hierarchy.searchSignalsRegex('Top/CPU/ALU/result');
      expect(results.length, 1);
      // signalId uses the normalised hierarchySeparator ('/') format
      // from the tree walker — findSignalById normalises both '.' and '/'.
      expect(results.first.signalId, 'Top/CPU/ALU/result');
      expect(results.first.signal, isNotNull);
      expect(results.first.signal!.name, 'result');
    });

    test('searchSignalsRegex returns results with SignalOccurrence objects',
        () {
      final results = hierarchy.searchSignalsRegex('Top/**/carry_out');
      expect(results.length, 1);
      expect(results.first.signal, isNotNull);
      expect(results.first.signal!.name, 'carry_out');
      expect(results.first.signal!.width, 1);
    });

    test('searchOccurrencesRegex returns OccurrenceSearchResult objects', () {
      final results = hierarchy.searchOccurrencesRegex('Top/**/Cache');
      expect(results.length, 1);
      expect(results.first.occurrenceId, 'Top/Memory/Cache');
    });

    // ── Limit ──

    test('limit controls maximum results', () {
      final results = hierarchy.searchSignalPathsRegex('Top/**/.+', limit: 3);
      expect(results.length, 3);
    });

    // ── Glob-style wildcards ──

    test('glob * at start matches suffix pattern', () {
      // User's scenario: "*m" should match signals ending in "m".
      final results = hierarchy.searchSignalPathsRegex('Top/*_m');
      expect(
          results,
          containsAll([
            'Top/data_m',
            'Top/addr_m',
            'Top/flag_m',
          ]));
      expect(results.length, 3);
    });

    test('glob * at end matches prefix pattern', () {
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/RegFile/d*');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/d0',
            'Top/CPU/RegFile/d1',
            'Top/CPU/RegFile/d2',
            'Top/CPU/RegFile/d15',
          ]));
      expect(results.length, 4);
    });

    test('glob * in the middle matches infix pattern', () {
      // *d*a* should match names containing 'd' followed eventually by 'a'
      final results =
          hierarchy.searchSignalPathsRegex('Top/Memory/Cache/*d*a*');
      expect(results, contains('Top/Memory/Cache/data'));
    });

    test('glob * matches all signals (like .*)', () {
      final results = hierarchy.searchSignalPathsRegex('Top/CPU/ALU/*');
      expect(
          results,
          containsAll([
            'Top/CPU/ALU/a',
            'Top/CPU/ALU/b',
            'Top/CPU/ALU/result',
            'Top/CPU/ALU/carry_out',
          ]));
      expect(results.length, 4);
    });

    test('glob * in module level matches any child', () {
      final results = hierarchy.searchSignalPathsRegex('Top/*/clk');
      // Top's immediate module-children are CPU, Memory, IO — none of
      // them have a direct clk signal, so this is empty.
      expect(results, isEmpty);
    });

    test('glob * combined with ** for deep search', () {
      final results = hierarchy.searchSignalPathsRegex('Top/**/*_m');
      expect(
          results,
          containsAll([
            'Top/data_m',
            'Top/addr_m',
            'Top/flag_m',
          ]));
      expect(results.length, 3);
    });

    // ── Empty / no match ──

    test('empty pattern returns nothing', () {
      expect(hierarchy.searchSignalPathsRegex(''), isEmpty);
      expect(hierarchy.searchOccurrencePathsRegex(''), isEmpty);
    });

    test('non-matching pattern returns nothing', () {
      expect(hierarchy.searchSignalPathsRegex('Top/NonExistent/foo'), isEmpty);
    });

    // ── ** at various positions ──

    test('trailing ** collects all signals below', () {
      final results = hierarchy.searchSignalPathsRegex('Top/Memory/**');
      // Should collect all signals in Memory subtree
      expect(
          results,
          containsAll([
            'Top/Memory/Cache/clk',
            'Top/Memory/Cache/addr',
            'Top/Memory/Cache/data',
            'Top/Memory/Cache/hit',
            'Top/Memory/DRAM/clk',
            'Top/Memory/DRAM/cas',
            'Top/Memory/DRAM/ras',
          ]));
      expect(results.length, 7);
    });

    test('multiple ** segments work', () {
      final results =
          hierarchy.searchSignalPathsRegex('**/(CPU|Memory)/**/clk');
      expect(
          results,
          containsAll([
            'Top/CPU/RegFile/clk',
            'Top/Memory/Cache/clk',
            'Top/Memory/DRAM/clk',
          ]));
    });
  });

  group('searchOccurrences dispatches to regex', () {
    late HierarchyService hierarchy;

    setUpAll(() {
      // Build hierarchy:
      // Top
      //   CPU
      //     ALU
      //     Decoder
      //     MuxUnit
      //   Memory
      //     Cache
      //     DRAM
      //   IO
      //     UART

      final alu = HierarchyOccurrence(
        name: 'ALU',
      );

      final decoder = HierarchyOccurrence(
        name: 'Decoder',
      );

      final muxUnit = HierarchyOccurrence(
        name: 'MuxUnit',
      );

      final cpu = HierarchyOccurrence(
        name: 'CPU',
        children: [alu, decoder, muxUnit],
      );

      final cache = HierarchyOccurrence(
        name: 'Cache',
      );

      final dram = HierarchyOccurrence(
        name: 'DRAM',
      );

      final memory = HierarchyOccurrence(
        name: 'Memory',
        children: [cache, dram],
      );

      final uart = HierarchyOccurrence(
        name: 'UART',
      );

      final io = HierarchyOccurrence(
        name: 'IO',
        children: [uart],
      );

      final root = HierarchyOccurrence(
        name: 'Top',
        children: [cpu, memory, io],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('searchOccurrences with glob pattern finds modules', () {
      // Pattern: *Mux* should find MuxUnit (auto-prepended with **/)
      final results = hierarchy.searchOccurrences('*Mux*');
      expect(results, isNotEmpty,
          reason:
              'searchOccurrences should dispatch to regex for glob patterns');
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchOccurrences with ** finds deep modules', () {
      final results = hierarchy.searchOccurrences('**/*Mux*');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchOccurrences with .* matches at one level', () {
      // */.*  matches any child one level below root
      final results = hierarchy.searchOccurrences('*/.*/.*');
      expect(results.length, greaterThanOrEqualTo(3),
          reason: 'Should match ALU, Decoder, MuxUnit, Cache, DRAM, UART');
    });

    test('searchOccurrences with explicit path pattern', () {
      // */CPU/.*  matches children of CPU
      final results = hierarchy.searchOccurrences('*/CPU/.*');
      expect(results.length, 3);
      expect(results.any((r) => r.name == 'ALU'), isTrue);
      expect(results.any((r) => r.name == 'Decoder'), isTrue);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchOccurrences with alternation', () {
      final results = hierarchy.searchOccurrences('**/(ALU|DRAM)');
      expect(results.length, 2);
      expect(results.any((r) => r.name == 'ALU'), isTrue);
      expect(results.any((r) => r.name == 'DRAM'), isTrue);
    });

    test('searchOccurrences without regex uses plain matching', () {
      // Plain query without glob chars uses substring matching
      final results = hierarchy.searchOccurrences('Mux');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchOccurrences with leading **/ is not double-prepended', () {
      final results = hierarchy.searchOccurrences('**/UART');
      expect(results.length, 1);
      expect(results.first.name, 'UART');
    });

    test('searchOccurrences with leading */ is not double-prepended', () {
      final results = hierarchy.searchOccurrences('*/CPU');
      expect(results.length, 1);
      expect(results.first.name, 'CPU');
    });
  });
}
