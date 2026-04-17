// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_search_test.dart
// Tests for module tree search functionality using hierarchy API.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('Module Tree Search - HierarchyService', () {
    late HierarchyNode root;
    late HierarchyService hierarchy;

    setUpAll(() {
      // Create a test hierarchy
      // Top
      //   CPU (2 children)
      //     ALU
      //     Decoder
      //   Memory
      //   ControlUnit

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

      final cpu = HierarchyNode(
        id: 'Top/CPU',
        name: 'CPU',
        kind: HierarchyKind.module,
        children: [alu, decoder],
      );

      final memory = HierarchyNode(
        id: 'Top/Memory',
        name: 'Memory',
        kind: HierarchyKind.module,
      );

      final controlUnit = HierarchyNode(
        id: 'Top/ControlUnit',
        name: 'ControlUnit',
        kind: HierarchyKind.module,
      );

      root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, memory, controlUnit],
      );

      // Use BaseHierarchyAdapter.fromTree to convert to HierarchyService
      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('root node is accessible', () {
      expect(hierarchy.root.name, equals('Top'));
      expect(hierarchy.root.kind, equals(HierarchyKind.module));
    });

    test('children of root are accessible', () {
      final children = hierarchy.root.children;
      expect(children, isNotEmpty);
      expect(children.length, equals(3));
      expect(children.any((c) => c.name == 'CPU'), isTrue);
    });

    test('searchNodePaths finds CPU module', () {
      final results = hierarchy.searchNodePaths('cpu');
      expect(results, isNotEmpty,
          reason: 'Should find CPU module by simple name');
      expect(results.any((path) => path.contains('CPU')), isTrue);
    });

    test('searchNodePaths finds ALU with hierarchical query', () {
      final results = hierarchy.searchNodePaths('cpu/alu');
      expect(results, isNotEmpty,
          reason: 'Should find ALU with hierarchical path');
      expect(results.any((path) => path.contains('ALU')), isTrue);
    });

    test('searchNodePaths works with dot notation', () {
      final results = hierarchy.searchNodePaths('top.cpu.alu');
      expect(results, isNotEmpty, reason: 'Should find ALU with dot notation');
      expect(results.any((path) => path.contains('Top/CPU/ALU')), isTrue);
    });

    test('searchNodePaths limits results', () {
      final results = hierarchy.searchNodePaths('', limit: 2);
      expect(results.length, lessThanOrEqualTo(2),
          reason: 'Should respect limit parameter');
    });

    test('searchModules returns ModuleSearchResult objects', () {
      final results = hierarchy.searchModules('memory');
      expect(results, isNotEmpty);
      expect(results.first, isA<ModuleSearchResult>());
      expect(results.first.name, equals('Memory'));
      expect(results.first.isModule, isTrue);
    });

    test('searchModules result contains full metadata', () {
      final results = hierarchy.searchModules('decoder');
      expect(results, isNotEmpty);
      final result = results.first;
      expect(result.moduleId, contains('Decoder'));
      expect(result.path, isNotEmpty);
      expect(result.path.last, equals('Decoder'));
      expect(result.node, isNotNull);
    });

    test('searchNodePaths returns empty for non-matching query', () {
      final results = hierarchy.searchNodePaths('nonexistent');
      expect(results, isEmpty,
          reason: 'Should return empty list for non-matching query');
    });

    test('searchNodePaths returns empty for empty query', () {
      final results = hierarchy.searchNodePaths('');
      expect(results, isEmpty,
          reason: 'Should return empty list for empty query');
    });

    test('searchModules finds modules at different depths', () {
      // Should find both Top and Top/CPU
      final results = hierarchy.searchModules('top');
      expect(results.length, greaterThanOrEqualTo(1));
      expect(results.any((r) => r.name == 'Top'), isTrue);
    });
  });

  group('Module Search - Hierarchical Matching', () {
    late HierarchyService hierarchy;

    setUpAll(() {
      // Create a deeper hierarchy to test matching
      // Design
      //   ProcessingUnit
      //     DataPath
      //       Multiplier
      //       Adder
      //     Controller
      //   Memory
      //     RAM
      //     Cache

      final multiplier = HierarchyNode(
        id: 'Design/ProcessingUnit/DataPath/Multiplier',
        name: 'Multiplier',
        kind: HierarchyKind.module,
      );

      final adder = HierarchyNode(
        id: 'Design/ProcessingUnit/DataPath/Adder',
        name: 'Adder',
        kind: HierarchyKind.module,
      );

      final dataPath = HierarchyNode(
        id: 'Design/ProcessingUnit/DataPath',
        name: 'DataPath',
        kind: HierarchyKind.module,
        children: [multiplier, adder],
      );

      final controller = HierarchyNode(
        id: 'Design/ProcessingUnit/Controller',
        name: 'Controller',
        kind: HierarchyKind.module,
      );

      final processingUnit = HierarchyNode(
        id: 'Design/ProcessingUnit',
        name: 'ProcessingUnit',
        kind: HierarchyKind.module,
        children: [dataPath, controller],
      );

      final ram = HierarchyNode(
        id: 'Design/Memory/RAM',
        name: 'RAM',
        kind: HierarchyKind.module,
      );

      final cache = HierarchyNode(
        id: 'Design/Memory/Cache',
        name: 'Cache',
        kind: HierarchyKind.module,
      );

      final memory = HierarchyNode(
        id: 'Design/Memory',
        name: 'Memory',
        kind: HierarchyKind.module,
        children: [ram, cache],
      );

      final root = HierarchyNode(
        id: 'Design',
        name: 'Design',
        kind: HierarchyKind.module,
        children: [processingUnit, memory],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('single segment matches at any level', () {
      final results = hierarchy.searchNodePaths('multiplier');
      expect(results, isNotEmpty,
          reason: 'Should find Multiplier even without full path');
      expect(results.any((r) => r.endsWith('Multiplier')), isTrue);
    });

    test('two segment path matches correctly', () {
      final results = hierarchy.searchNodePaths('datapath/multiplier');
      expect(results.any((r) => r.contains('DataPath/Multiplier')), isTrue,
          reason: 'Should find Multiplier under DataPath');
    });

    test('full hierarchical path matches precisely', () {
      final results =
          hierarchy.searchNodePaths('processingunit/datapath/adder');
      expect(results.any((r) => r.contains('ProcessingUnit/DataPath/Adder')),
          isTrue,
          reason: 'Should find Adder with full hierarchical path');
    });

    test('case insensitive matching works', () {
      final resultsLower = hierarchy.searchNodePaths('MULTIPLIER');
      final resultsUpper = hierarchy.searchNodePaths('multiplier');
      expect(resultsLower, isNotEmpty);
      expect(resultsUpper, isNotEmpty);
      expect(resultsLower.length, equals(resultsUpper.length),
          reason: 'Case should not affect matching');
    });

    test('partial name matching works', () {
      final results1 = hierarchy.searchNodePaths('path');
      expect(results1.any((r) => r.contains('DataPath')), isTrue,
          reason: 'Should match partial "path" in DataPath');

      final results2 = hierarchy.searchNodePaths('unit');
      expect(results2.any((r) => r.contains('ProcessingUnit')), isTrue,
          reason: 'Should match partial "unit" in ProcessingUnit');
    });
  });

  group('Module Search - Integration with Tree Filtering', () {
    late HierarchyNode root;

    setUpAll(() {
      final alu = HierarchyNode(
        id: 'Top/CPU/ALU',
        name: 'ALU',
        kind: HierarchyKind.module,
      );

      final cpu = HierarchyNode(
        id: 'Top/CPU',
        name: 'CPU',
        kind: HierarchyKind.module,
        children: [alu],
      );

      final memory = HierarchyNode(
        id: 'Top/Memory',
        name: 'Memory',
        kind: HierarchyKind.module,
      );

      root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, memory],
      );
    });

    test('hierarchical filtering shows root when descendant matches', () {
      final matchesSearch = _filterNodeRecursive(root, 'alu');
      expect(matchesSearch, isTrue,
          reason: 'Root should be shown because descendant matches');
    });

    test('hierarchical filtering shows parent of matching child', () {
      final cpuNode = root.children.first;
      final cpuMatches = _filterNodeRecursive(cpuNode, 'alu');
      expect(cpuMatches, isTrue,
          reason: 'CPU should be shown because child ALU matches');
    });

    test('hierarchical filtering hides node without matching descendants', () {
      final memoryNode = root.children.last;
      final memoryMatches = _filterNodeRecursive(memoryNode, 'alu');
      expect(memoryMatches, isFalse,
          reason: 'Memory should be hidden because no ALU descendant');
    });

    test('path separator search shows root for hierarchical match', () {
      final matchesSearch = _filterNodeRecursive(root, 'cpu/alu');
      expect(matchesSearch, isTrue,
          reason: 'Root should be shown for hierarchical search');
    });

    test('path separator search shows matching parent', () {
      final cpuNode = root.children.first;
      final cpuMatches = _filterNodeRecursive(cpuNode, 'cpu/alu');
      expect(cpuMatches, isTrue,
          reason: 'CPU should be shown for hierarchical search');
    });

    test('path separator search hides non-matching subtree', () {
      final memoryNode = root.children.last;
      final memoryMatches = _filterNodeRecursive(memoryNode, 'cpu/alu');
      expect(memoryMatches, isFalse,
          reason: 'Memory should be hidden for non-matching path');
    });
  });
}

/// Helper function to simulate tree filtering with hierarchical search.
/// Matches query against node name using hierarchical logic.
bool _filterNodeRecursive(HierarchyNode node, String query) {
  final queryParts = query
      .replaceAll('.', '/')
      .toLowerCase()
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  return _matchesHierarchicalQuery(node, queryParts, 0);
}

bool _matchesHierarchicalQuery(
    HierarchyNode node, List<String> queryParts, int queryIdx) {
  if (queryIdx >= queryParts.length) {
    return true;
  }

  final currentQueryPart = queryParts[queryIdx].toLowerCase();
  final nodeName = node.name.toLowerCase();

  final matched = nodeName.contains(currentQueryPart);
  final nextQueryIdx = matched ? queryIdx + 1 : queryIdx;

  if (nextQueryIdx >= queryParts.length) {
    return true;
  }

  for (final child in node.children) {
    if (_matchesHierarchicalQuery(child, queryParts, nextQueryIdx)) {
      return true;
    }
  }

  return false;
}
