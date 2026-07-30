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
    late HierarchyOccurrence root;
    late HierarchyService hierarchy;

    setUpAll(() {
      // Create a test hierarchy
      // Top
      //   CPU (2 children)
      //     ALU
      //     Decoder
      //   Memory
      //   ControlUnit

      final alu = HierarchyOccurrence(
        name: 'ALU',
      );

      final decoder = HierarchyOccurrence(
        name: 'Decoder',
      );

      final cpu = HierarchyOccurrence(
        name: 'CPU',
        children: [alu, decoder],
      );

      final memory = HierarchyOccurrence(
        name: 'Memory',
      );

      final controlUnit = HierarchyOccurrence(
        name: 'ControlUnit',
      );

      root = HierarchyOccurrence(
        name: 'Top',
        children: [cpu, memory, controlUnit],
      );

      // Use BaseHierarchyAdapter.fromTree to convert to HierarchyService
      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('root node is accessible', () {
      expect(hierarchy.root.name, equals('Top'));
      expect(hierarchy.root.isPrimitive, isFalse);
    });

    test('children of root are accessible', () {
      final children = hierarchy.root.children;
      expect(children, isNotEmpty);
      expect(children.length, equals(3));
      expect(children.any((c) => c.name == 'CPU'), isTrue);
    });

    test('searchNodePaths finds CPU module', () {
      final results = hierarchy.searchOccurrencePaths('CPU');
      expect(results, isNotEmpty,
          reason: 'Should find CPU module by simple name');
      expect(results.any((path) => path.contains('CPU')), isTrue);
    });

    test('searchNodePaths finds ALU with hierarchical query', () {
      final results = hierarchy.searchOccurrencePaths('CPU/ALU');
      expect(results, isNotEmpty,
          reason: 'Should find ALU with hierarchical path');
      expect(results.any((path) => path.contains('ALU')), isTrue);
    });

    test('searchNodePaths works with dot notation', () {
      final results = hierarchy.searchOccurrencePaths('Top.CPU.ALU');
      expect(results, isNotEmpty, reason: 'Should find ALU with dot notation');
      expect(results.any((path) => path.contains('Top/CPU/ALU')), isTrue);
    });

    test('searchNodePaths limits results', () {
      final results = hierarchy.searchOccurrencePaths('', limit: 2);
      expect(results.length, lessThanOrEqualTo(2),
          reason: 'Should respect limit parameter');
    });

    test('searchModules returns ModuleSearchResult objects', () {
      final results = hierarchy.searchOccurrences('Memory');
      expect(results, isNotEmpty);
      expect(results.first, isA<OccurrenceSearchResult>());
      expect(results.first.name, equals('Memory'));
      expect(results.first.isModule, isTrue);
    });

    test('searchModules result contains full metadata', () {
      final results = hierarchy.searchOccurrences('Decoder');
      expect(results, isNotEmpty);
      final result = results.first;
      expect(result.occurrenceId, contains('Decoder'));
      expect(result.path, isNotEmpty);
      expect(result.path.last, equals('Decoder'));
      expect(result.occurrence, isNotNull);
    });

    test('searchNodePaths returns empty for non-matching query', () {
      final results = hierarchy.searchOccurrencePaths('nonexistent');
      expect(results, isEmpty,
          reason: 'Should return empty list for non-matching query');
    });

    test('searchNodePaths returns empty for empty query', () {
      final results = hierarchy.searchOccurrencePaths('');
      expect(results, isEmpty,
          reason: 'Should return empty list for empty query');
    });

    test('searchModules finds modules at different depths', () {
      // Should find both Top and Top/CPU
      final results = hierarchy.searchOccurrences('Top');
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

      final multiplier = HierarchyOccurrence(
        name: 'Multiplier',
      );

      final adder = HierarchyOccurrence(
        name: 'Adder',
      );

      final dataPath = HierarchyOccurrence(
        name: 'DataPath',
        children: [multiplier, adder],
      );

      final controller = HierarchyOccurrence(
        name: 'Controller',
      );

      final processingUnit = HierarchyOccurrence(
        name: 'ProcessingUnit',
        children: [dataPath, controller],
      );

      final ram = HierarchyOccurrence(
        name: 'RAM',
      );

      final cache = HierarchyOccurrence(
        name: 'Cache',
      );

      final memory = HierarchyOccurrence(
        name: 'Memory',
        children: [ram, cache],
      );

      final root = HierarchyOccurrence(
        name: 'Design',
        children: [processingUnit, memory],
      );

      hierarchy = BaseHierarchyAdapter.fromTree(root);
    });

    test('single segment matches at any level', () {
      final results = hierarchy.searchOccurrencePaths('Multiplier');
      expect(results, isNotEmpty,
          reason: 'Should find Multiplier even without full path');
      expect(results.any((r) => r.endsWith('Multiplier')), isTrue);
    });

    test('two segment path matches correctly', () {
      final results = hierarchy.searchOccurrencePaths('DataPath/Multiplier');
      expect(results.any((r) => r.contains('DataPath/Multiplier')), isTrue,
          reason: 'Should find Multiplier under DataPath');
    });

    test('full hierarchical path matches precisely', () {
      final results =
          hierarchy.searchOccurrencePaths('ProcessingUnit/DataPath/Adder');
      expect(results.any((r) => r.contains('ProcessingUnit/DataPath/Adder')),
          isTrue,
          reason: 'Should find Adder with full hierarchical path');
    });

    test('partial name matching works', () {
      final results1 = hierarchy.searchOccurrencePaths('Path');
      expect(results1.any((r) => r.contains('DataPath')), isTrue,
          reason: 'Should match partial "path" in DataPath');

      final results2 = hierarchy.searchOccurrencePaths('Unit');
      expect(results2.any((r) => r.contains('ProcessingUnit')), isTrue,
          reason: 'Should match partial "unit" in ProcessingUnit');
    });
  });

  group('Module Search - Integration with Tree Filtering', () {
    late HierarchyOccurrence root;

    setUpAll(() {
      final alu = HierarchyOccurrence(
        name: 'ALU',
      );

      final cpu = HierarchyOccurrence(
        name: 'CPU',
        children: [alu],
      );

      final memory = HierarchyOccurrence(
        name: 'Memory',
      );

      root = HierarchyOccurrence(
        name: 'Top',
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
bool _filterNodeRecursive(HierarchyOccurrence node, String query) {
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
    HierarchyOccurrence node, List<String> queryParts, int queryIdx) {
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
