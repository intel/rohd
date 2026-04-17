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

      final alu = HierarchyNode(
        id: 'Top.CPU.ALU',
        name: 'ALU',
        kind: HierarchyKind.module,
        signals: [
          Signal(type: 'wire', id: 'Top.CPU.ALU.a', name: 'a', width: 8),
          Signal(type: 'wire', id: 'Top.CPU.ALU.b', name: 'b', width: 8),
          Signal(
              type: 'wire', id: 'Top.CPU.ALU.result', name: 'result', width: 8),
          Signal(
              type: 'wire',
              id: 'Top.CPU.ALU.carry_out',
              name: 'carry_out',
              width: 1),
        ],
      );

      final decoder = HierarchyNode(
        id: 'Top.CPU.Decoder',
        name: 'Decoder',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              type: 'wire',
              id: 'Top.CPU.Decoder.opcode',
              name: 'opcode',
              width: 4),
          Signal(
              type: 'wire',
              id: 'Top.CPU.Decoder.enable',
              name: 'enable',
              width: 1),
        ],
      );

      final regFile = HierarchyNode(
        id: 'Top.CPU.RegFile',
        name: 'RegFile',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              type: 'wire', id: 'Top.CPU.RegFile.clk', name: 'clk', width: 1),
          Signal(
              type: 'wire',
              id: 'Top.CPU.RegFile.reset',
              name: 'reset',
              width: 1),
          Signal(type: 'wire', id: 'Top.CPU.RegFile.d0', name: 'd0', width: 8),
          Signal(type: 'wire', id: 'Top.CPU.RegFile.d1', name: 'd1', width: 8),
          Signal(type: 'wire', id: 'Top.CPU.RegFile.d2', name: 'd2', width: 8),
          Signal(
              type: 'wire', id: 'Top.CPU.RegFile.d15', name: 'd15', width: 8),
        ],
      );

      final cpu = HierarchyNode(
        id: 'Top.CPU',
        name: 'CPU',
        kind: HierarchyKind.module,
        children: [alu, decoder, regFile],
      );

      final cache = HierarchyNode(
        id: 'Top.Memory.Cache',
        name: 'Cache',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              type: 'wire', id: 'Top.Memory.Cache.clk', name: 'clk', width: 1),
          Signal(
              type: 'wire',
              id: 'Top.Memory.Cache.addr',
              name: 'addr',
              width: 16),
          Signal(
              type: 'wire',
              id: 'Top.Memory.Cache.data',
              name: 'data',
              width: 32),
          Signal(
              type: 'wire', id: 'Top.Memory.Cache.hit', name: 'hit', width: 1),
        ],
      );

      final dram = HierarchyNode(
        id: 'Top.Memory.DRAM',
        name: 'DRAM',
        kind: HierarchyKind.module,
        signals: [
          Signal(
              type: 'wire', id: 'Top.Memory.DRAM.clk', name: 'clk', width: 1),
          Signal(
              type: 'wire', id: 'Top.Memory.DRAM.cas', name: 'cas', width: 1),
          Signal(
              type: 'wire', id: 'Top.Memory.DRAM.ras', name: 'ras', width: 1),
        ],
      );

      final memory = HierarchyNode(
        id: 'Top.Memory',
        name: 'Memory',
        kind: HierarchyKind.module,
        children: [cache, dram],
      );

      final uart = HierarchyNode(
        id: 'Top.IO.UART',
        name: 'UART',
        kind: HierarchyKind.module,
        signals: [
          Signal(type: 'wire', id: 'Top.IO.UART.clk', name: 'clk', width: 1),
          Signal(type: 'wire', id: 'Top.IO.UART.tx', name: 'tx', width: 1),
          Signal(type: 'wire', id: 'Top.IO.UART.rx', name: 'rx', width: 1),
        ],
      );

      final io = HierarchyNode(
        id: 'Top.IO',
        name: 'IO',
        kind: HierarchyKind.module,
        children: [uart],
      );

      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, memory, io],
        signals: [
          Signal(type: 'wire', id: 'Top.clk', name: 'clk', width: 1),
          Signal(type: 'wire', id: 'Top.reset', name: 'reset', width: 1),
          Signal(type: 'wire', id: 'Top.data_m', name: 'data_m', width: 8),
          Signal(type: 'wire', id: 'Top.addr_m', name: 'addr_m', width: 16),
          Signal(type: 'wire', id: 'Top.flag_m', name: 'flag_m', width: 1),
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

    // ── Case insensitivity ──

    test('search is case-insensitive', () {
      final results = hierarchy.searchSignalPathsRegex('top/cpu/alu/RESULT');
      expect(results, contains('Top/CPU/ALU/result'));
    });

    // ── Module search ──

    test('searchNodePathsRegex finds modules', () {
      final results = hierarchy.searchNodePathsRegex('Top/CPU/.*');
      expect(
          results,
          containsAll([
            'Top/CPU/ALU',
            'Top/CPU/Decoder',
            'Top/CPU/RegFile',
          ]));
    });

    test('searchNodePathsRegex with **', () {
      final results = hierarchy.searchNodePathsRegex('Top/**/DRAM');
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

    test('searchSignalsRegex returns results with Signal objects', () {
      final results = hierarchy.searchSignalsRegex('Top/**/carry_out');
      expect(results.length, 1);
      expect(results.first.signal, isNotNull);
      expect(results.first.signal!.name, 'carry_out');
      expect(results.first.signal!.width, 1);
    });

    test('searchModulesRegex returns ModuleSearchResult objects', () {
      final results = hierarchy.searchModulesRegex('Top/**/Cache');
      expect(results.length, 1);
      expect(results.first.moduleId, 'Top/Memory/Cache');
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
      expect(hierarchy.searchNodePathsRegex(''), isEmpty);
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

  group('searchModules dispatches to regex', () {
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

      final alu = HierarchyNode(
        id: 'Top/CPU/ALU',
        name: 'ALU',
        kind: HierarchyKind.module,
      );

      final decoder = HierarchyNode(
        id: 'Top/CPU/Decoder',
        name: 'Decoder',
        kind: HierarchyKind.module,
      );

      final muxUnit = HierarchyNode(
        id: 'Top/CPU/MuxUnit',
        name: 'MuxUnit',
        kind: HierarchyKind.module,
      );

      final cpu = HierarchyNode(
        id: 'Top/CPU',
        name: 'CPU',
        kind: HierarchyKind.module,
        children: [alu, decoder, muxUnit],
      );

      final cache = HierarchyNode(
        id: 'Top/Memory/Cache',
        name: 'Cache',
        kind: HierarchyKind.module,
      );

      final dram = HierarchyNode(
        id: 'Top/Memory/DRAM',
        name: 'DRAM',
        kind: HierarchyKind.module,
      );

      final memory = HierarchyNode(
        id: 'Top/Memory',
        name: 'Memory',
        kind: HierarchyKind.module,
        children: [cache, dram],
      );

      final uart = HierarchyNode(
        id: 'Top/IO/UART',
        name: 'UART',
        kind: HierarchyKind.module,
      );

      final io = HierarchyNode(
        id: 'Top/IO',
        name: 'IO',
        kind: HierarchyKind.module,
        children: [uart],
      );

      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, memory, io],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('searchModules with glob pattern finds modules', () {
      // Pattern: *mux* should find MuxUnit (auto-prepended with */)
      final results = hierarchy.searchModules('*mux*');
      expect(results, isNotEmpty,
          reason: 'searchModules should dispatch to regex for glob patterns');
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchModules with ** finds deep modules', () {
      final results = hierarchy.searchModules('**/*mux*');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchModules with .* matches at one level', () {
      // */.*  matches any child one level below root
      final results = hierarchy.searchModules('*/.*/.*');
      expect(results.length, greaterThanOrEqualTo(3),
          reason: 'Should match ALU, Decoder, MuxUnit, Cache, DRAM, UART');
    });

    test('searchModules with explicit path pattern', () {
      // */CPU/.*  matches children of CPU
      final results = hierarchy.searchModules('*/CPU/.*');
      expect(results.length, 3);
      expect(results.any((r) => r.name == 'ALU'), isTrue);
      expect(results.any((r) => r.name == 'Decoder'), isTrue);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchModules with alternation', () {
      final results = hierarchy.searchModules('**/(ALU|DRAM)');
      expect(results.length, 2);
      expect(results.any((r) => r.name == 'ALU'), isTrue);
      expect(results.any((r) => r.name == 'DRAM'), isTrue);
    });

    test('searchModules without regex uses plain matching', () {
      // Plain query without glob chars uses substring matching
      final results = hierarchy.searchModules('mux');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.name == 'MuxUnit'), isTrue);
    });

    test('searchModules with leading **/ is not double-prepended', () {
      final results = hierarchy.searchModules('**/UART');
      expect(results.length, 1);
      expect(results.first.name, 'UART');
    });

    test('searchModules with leading */ is not double-prepended', () {
      final results = hierarchy.searchModules('*/CPU');
      expect(results.length, 1);
      expect(results.first.name, 'CPU');
    });
  });
}
