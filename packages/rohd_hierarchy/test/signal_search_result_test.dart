// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_search_result_test.dart
// Tests for SignalSearchResult and ModuleSearchResult display helpers.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('SignalSearchResult display helpers', () {
    test('displayPath strips top module', () {
      const result = SignalSearchResult(
        signalId: 'Top/counter/clk',
        path: ['Top', 'counter', 'clk'],
      );
      expect(result.displayPath, equals('counter/clk'));
    });

    test('displayPath for top-level signal', () {
      const result = SignalSearchResult(
        signalId: 'Top/clk',
        path: ['Top', 'clk'],
      );
      expect(result.displayPath, equals('clk'));
    });

    test('displayPath for single-segment path', () {
      const result = SignalSearchResult(
        signalId: 'clk',
        path: ['clk'],
      );
      expect(result.displayPath, equals('clk'));
    });

    test('displaySegments strips top module', () {
      const result = SignalSearchResult(
        signalId: 'Top/sub1/sub2/clk',
        path: ['Top', 'sub1', 'sub2', 'clk'],
      );
      expect(result.displaySegments, equals(['sub1', 'sub2', 'clk']));
    });

    test('intermediateInstanceNames extracts middle segments', () {
      const result = SignalSearchResult(
        signalId: 'Top/sub1/sub2/clk',
        path: ['Top', 'sub1', 'sub2', 'clk'],
      );
      expect(result.intermediateInstanceNames, equals(['sub1', 'sub2']));
    });

    test('intermediateInstanceNames empty for top-level signal', () {
      const result = SignalSearchResult(
        signalId: 'Top/clk',
        path: ['Top', 'clk'],
      );
      expect(result.intermediateInstanceNames, isEmpty);
    });

    test('intermediateInstanceNames empty for single-level nesting', () {
      const result = SignalSearchResult(
        signalId: 'Top/sub1/clk',
        path: ['Top', 'sub1', 'clk'],
      );
      // sub1 is both the containing block and an intermediate instance
      expect(result.intermediateInstanceNames, equals(['sub1']));
    });

    test('name returns last path segment', () {
      const result = SignalSearchResult(
        signalId: 'Top/counter/clk',
        path: ['Top', 'counter', 'clk'],
      );
      expect(result.name, equals('clk'));
    });

    test('equality based on signalId', () {
      const a = SignalSearchResult(
        signalId: 'Top/clk',
        path: ['Top', 'clk'],
      );
      const b = SignalSearchResult(
        signalId: 'Top/clk',
        path: ['Top', 'clk'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SignalSearchResult.normalizeQuery', () {
    test('converts dots to slashes', () {
      expect(
        SignalSearchResult.normalizeQuery('top.cpu.clk'),
        equals('top/cpu/clk'),
      );
    });

    test('preserves slashes', () {
      expect(
        SignalSearchResult.normalizeQuery('top/cpu/clk'),
        equals('top/cpu/clk'),
      );
    });

    test('handles mixed separators', () {
      expect(
        SignalSearchResult.normalizeQuery('top.cpu/clk'),
        equals('top/cpu/clk'),
      );
    });

    test('handles empty query', () {
      expect(SignalSearchResult.normalizeQuery(''), equals(''));
    });
  });

  group('ModuleSearchResult display helpers', () {
    late HierarchyNode aluNode;

    setUp(() {
      aluNode = HierarchyNode(
        id: 'Top/CPU/ALU',
        name: 'ALU',
        kind: HierarchyKind.module,
      );
    });

    test('displayPath strips top module', () {
      final result = ModuleSearchResult(
        moduleId: 'Top/CPU/ALU',
        path: const ['Top', 'CPU', 'ALU'],
        node: aluNode,
      );
      expect(result.displayPath, equals('CPU/ALU'));
    });

    test('displaySegments strips top module', () {
      final result = ModuleSearchResult(
        moduleId: 'Top/CPU/ALU',
        path: const ['Top', 'CPU', 'ALU'],
        node: aluNode,
      );
      expect(result.displaySegments, equals(['CPU', 'ALU']));
    });

    test('displayPath for single-segment path', () {
      final topNode = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
      );
      final result = ModuleSearchResult(
        moduleId: 'Top',
        path: const ['Top'],
        node: topNode,
      );
      expect(result.displayPath, equals('Top'));
    });

    test('equality based on moduleId', () {
      final a = ModuleSearchResult(
        moduleId: 'Top/CPU/ALU',
        path: const ['Top', 'CPU', 'ALU'],
        node: aluNode,
      );
      final b = ModuleSearchResult(
        moduleId: 'Top/CPU/ALU',
        path: const ['Top', 'CPU', 'ALU'],
        node: aluNode,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ModuleSearchResult.normalizeQuery', () {
    test('converts dots to slashes', () {
      expect(
        ModuleSearchResult.normalizeQuery('top.cpu'),
        equals('top/cpu'),
      );
    });
  });

  group('searchSignals integration with display helpers', () {
    late HierarchyService hierarchy;

    setUpAll(() {
      // Build: Top -> counter (with clk, data[8] signals)
      final counter = HierarchyNode(
        id: 'Top/counter',
        name: 'counter',
        kind: HierarchyKind.module,
        signals: [
          Signal(
            id: 'Top/counter/clk',
            name: 'clk',
            type: 'wire',
            width: 1,
            fullPath: 'Top/counter/clk',
            scopeId: 'Top/counter',
          ),
          Signal(
            id: 'Top/counter/data',
            name: 'data',
            type: 'wire',
            width: 8,
            fullPath: 'Top/counter/data',
            scopeId: 'Top/counter',
          ),
        ],
      );

      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [counter],
        signals: [
          Port(
            id: 'Top/reset',
            name: 'reset',
            type: 'wire',
            width: 1,
            direction: 'input',
            fullPath: 'Top/reset',
            scopeId: 'Top',
          ),
        ],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('searchSignals returns enriched results', () {
      final results = hierarchy.searchSignals('clk');
      expect(results, isNotEmpty);
      final result = results.first;
      expect(result.signalId, contains('clk'));
      expect(result.displayPath, equals('counter/clk'));
      expect(result.intermediateInstanceNames, equals(['counter']));
    });

    test('searchSignals for top-level port', () {
      final results = hierarchy.searchSignals('reset');
      expect(results, isNotEmpty);
      final result = results.first;
      expect(result.displayPath, equals('reset'));
      expect(result.intermediateInstanceNames, isEmpty);
    });
  });
}
