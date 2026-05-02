// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_search_controller_test.dart
// Tests for HierarchySearchController.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Minimal hierarchy for testing the controller with a real
/// HierarchyService.
HierarchyNode _buildTestTree() => HierarchyNode(
      id: 'Top',
      name: 'Top',
      kind: HierarchyKind.module,
      signals: [
        Signal(id: 'Top/clk', name: 'clk', type: 'wire', width: 1),
        Signal(id: 'Top/rst', name: 'rst', type: 'wire', width: 1),
      ],
      children: [
        HierarchyNode(
          id: 'Top/cpu',
          name: 'cpu',
          kind: HierarchyKind.instance,
          parentId: 'Top',
          signals: [
            Signal(
                id: 'Top/cpu/data_in', name: 'data_in', type: 'wire', width: 8),
            Signal(
                id: 'Top/cpu/data_out',
                name: 'data_out',
                type: 'wire',
                width: 8),
          ],
          children: [
            HierarchyNode(
              id: 'Top/cpu/alu',
              name: 'alu',
              kind: HierarchyKind.instance,
              parentId: 'Top/cpu',
              signals: [
                Signal(id: 'Top/cpu/alu/a', name: 'a', type: 'wire', width: 16),
                Signal(id: 'Top/cpu/alu/b', name: 'b', type: 'wire', width: 16),
                Signal(
                    id: 'Top/cpu/alu/result',
                    name: 'result',
                    type: 'wire',
                    width: 16),
              ],
            ),
          ],
        ),
        HierarchyNode(
          id: 'Top/mem',
          name: 'mem',
          kind: HierarchyKind.instance,
          parentId: 'Top',
          signals: [
            Signal(id: 'Top/mem/addr', name: 'addr', type: 'wire', width: 32),
          ],
        ),
      ],
    );

void main() {
  late BaseHierarchyAdapter hierarchy;
  late HierarchySearchController<SignalSearchResult> signalCtrl;
  late HierarchySearchController<ModuleSearchResult> moduleCtrl;

  setUp(() {
    hierarchy = BaseHierarchyAdapter.fromTree(_buildTestTree());
    signalCtrl = HierarchySearchController.forSignals(hierarchy);
    moduleCtrl = HierarchySearchController.forModules(hierarchy);
  });

  group('HierarchySearchController — signal search', () {
    test('starts with empty state', () {
      expect(signalCtrl.results, isEmpty);
      expect(signalCtrl.selectedIndex, 0);
      expect(signalCtrl.hasResults, isFalse);
      expect(signalCtrl.counterText, isEmpty);
      expect(signalCtrl.currentSelection, isNull);
    });

    test('updateQuery populates results', () {
      signalCtrl.updateQuery('clk');
      expect(signalCtrl.hasResults, isTrue);
      expect(signalCtrl.results.first.name, 'clk');
      expect(signalCtrl.selectedIndex, 0);
    });

    test('updateQuery with empty string clears results', () {
      signalCtrl.updateQuery('clk');
      expect(signalCtrl.hasResults, isTrue);

      signalCtrl.updateQuery('');
      expect(signalCtrl.hasResults, isFalse);
      expect(signalCtrl.selectedIndex, 0);
    });

    test('updateQuery resets selectedIndex', () {
      signalCtrl
        ..updateQuery('data')
        ..selectNext(); // index 1
      expect(signalCtrl.selectedIndex, 1);

      signalCtrl.updateQuery('data'); // re-search
      expect(signalCtrl.selectedIndex, 0); // reset
    });

    test('normalise converts dots to slashes', () {
      signalCtrl.updateQuery('cpu.alu.a');
      expect(signalCtrl.hasResults, isTrue);
      expect(signalCtrl.results.first.name, 'a');
    });

    test('counterText is correct', () {
      signalCtrl.updateQuery('data');
      expect(signalCtrl.counterText, '1/${signalCtrl.results.length}');

      signalCtrl.selectNext();
      expect(signalCtrl.counterText, '2/${signalCtrl.results.length}');
    });

    test('currentSelection returns the highlighted result', () {
      signalCtrl.updateQuery('data');
      final first = signalCtrl.currentSelection;
      expect(first, isNotNull);
      expect(first!.name, 'data_in');

      signalCtrl.selectNext();
      expect(signalCtrl.currentSelection!.name, 'data_out');
    });

    test('selectNext wraps around', () {
      signalCtrl.updateQuery('data');
      final count = signalCtrl.results.length;
      expect(count, greaterThan(1));

      for (var i = 0; i < count; i++) {
        signalCtrl.selectNext();
      }
      expect(signalCtrl.selectedIndex, 0); // wrapped
    });

    test('selectPrevious wraps around', () {
      signalCtrl
        ..updateQuery('data')
        ..selectPrevious(); // wraps from 0 → last
      expect(signalCtrl.selectedIndex, signalCtrl.results.length - 1);
    });

    test('selectNext/selectPrevious no-op when empty', () {
      signalCtrl.selectNext();
      expect(signalCtrl.selectedIndex, 0);
      signalCtrl.selectPrevious();
      expect(signalCtrl.selectedIndex, 0);
    });

    test('clear resets everything', () {
      signalCtrl
        ..updateQuery('data')
        ..selectNext();
      expect(signalCtrl.hasResults, isTrue);
      expect(signalCtrl.selectedIndex, greaterThan(0));

      signalCtrl.clear();
      expect(signalCtrl.results, isEmpty);
      expect(signalCtrl.selectedIndex, 0);
      expect(signalCtrl.currentSelection, isNull);
    });

    test('no results for non-matching query', () {
      signalCtrl.updateQuery('xyz_no_match');
      expect(signalCtrl.hasResults, isFalse);
      expect(signalCtrl.counterText, isEmpty);
    });

    test('plain query uses prefix match, not substring', () {
      // 'a' should match signals starting with 'a' (addr, a),
      // but NOT signals that merely contain 'a' (data_in, data_out).
      signalCtrl.updateQuery('a');
      final names = signalCtrl.results.map((r) => r.name).toList();
      expect(names, contains('a')); // Top/cpu/alu/a
      expect(names, contains('addr')); // Top/mem/addr
      expect(names, isNot(contains('data_in'))); // 'a' is not a prefix
      expect(names, isNot(contains('data_out')));
    });

    test('glob * pattern routes to regex search', () {
      // 'cpu/*_out' should match signals ending in '_out' under cpu
      // (single-segment globs like '*_out' only search root-level;
      //  use a path segment to target a child module).
      signalCtrl.updateQuery('cpu/*_out');
      expect(signalCtrl.hasResults, isTrue);
      final names = signalCtrl.results.map((r) => r.name).toList();
      expect(names, contains('data_out'));
      expect(names, isNot(contains('data_in')));
    });

    test('glob * at end matches prefix', () {
      signalCtrl.updateQuery('cpu/data*');
      final names = signalCtrl.results.map((r) => r.name).toList();
      expect(names, containsAll(['data_in', 'data_out']));
    });

    test('glob * at root matches top-level signals', () {
      // Single-segment glob only searches root module signals.
      signalCtrl.updateQuery('*st');
      expect(signalCtrl.hasResults, isTrue);
      final names = signalCtrl.results.map((r) => r.name).toList();
      expect(names, contains('rst'));
    });
  });

  group('HierarchySearchController — module search', () {
    test('finds modules by name', () {
      moduleCtrl.updateQuery('cpu');
      expect(moduleCtrl.hasResults, isTrue);
      expect(moduleCtrl.results.first.node.name, 'cpu');
    });

    test('finds nested modules', () {
      moduleCtrl.updateQuery('alu');
      expect(moduleCtrl.hasResults, isTrue);
      expect(moduleCtrl.results.first.node.name, 'alu');
    });

    test('counterText and selection work for modules', () {
      moduleCtrl.updateQuery('m'); // matches 'mem', possibly others
      expect(moduleCtrl.hasResults, isTrue);
      expect(moduleCtrl.counterText, isNotEmpty);
      expect(moduleCtrl.currentSelection, isNotNull);
    });
  });

  group('scrollOffsetToReveal', () {
    test('returns null when item is visible', () {
      final offset = HierarchySearchController.scrollOffsetToReveal(
        selectedIndex: 2,
        itemHeight: 48,
        viewportHeight: 300,
        currentOffset: 0,
      );
      // item at 96..144, viewport 0..300 → visible
      expect(offset, isNull);
    });

    test('scrolls up when item is above viewport', () {
      final offset = HierarchySearchController.scrollOffsetToReveal(
        selectedIndex: 0,
        itemHeight: 48,
        viewportHeight: 300,
        currentOffset: 100,
      );
      // item at 0..48, viewport starts at 100 → need to scroll to 0
      expect(offset, 0.0);
    });

    test('scrolls down when item is below viewport', () {
      final offset = HierarchySearchController.scrollOffsetToReveal(
        selectedIndex: 10,
        itemHeight: 48,
        viewportHeight: 200,
        currentOffset: 0,
      );
      // item at 480..528, viewport 0..200 → scroll to 528-200 = 328
      expect(offset, 328.0);
    });

    test('returns null when item is at bottom edge', () {
      final offset = HierarchySearchController.scrollOffsetToReveal(
        selectedIndex: 4,
        itemHeight: 50,
        viewportHeight: 250,
        currentOffset: 0,
      );
      // item at 200..250, viewport 0..250 → exactly visible
      expect(offset, isNull);
    });
  });

  // ------------------------------------------------------------------
  // VCD-style dot-separated paths
  // ------------------------------------------------------------------
  group('VCD dot-separated paths', () {
    late BaseHierarchyAdapter vcdHierarchy;

    setUp(() {
      // VCD/FST files produce dot-separated IDs like "testbench.childA.clk"
      vcdHierarchy = BaseHierarchyAdapter.fromTree(
        HierarchyNode(
          id: 'testbench',
          name: 'testbench',
          kind: HierarchyKind.module,
          signals: [
            Signal(id: 'testbench.clk', name: 'clk', type: 'wire', width: 1),
            Signal(id: 'testbench.rst', name: 'rst', type: 'wire', width: 1),
          ],
          children: [
            HierarchyNode(
              id: 'testbench.childA',
              name: 'childA',
              kind: HierarchyKind.instance,
              parentId: 'testbench',
              signals: [
                Signal(
                    id: 'testbench.childA.clk',
                    name: 'clk',
                    type: 'wire',
                    width: 1),
                Signal(
                    id: 'testbench.childA.data',
                    name: 'data',
                    type: 'wire',
                    width: 8),
              ],
              children: [
                HierarchyNode(
                  id: 'testbench.childA.sub',
                  name: 'sub',
                  kind: HierarchyKind.instance,
                  parentId: 'testbench.childA',
                  signals: [
                    Signal(
                        id: 'testbench.childA.sub.out',
                        name: 'out',
                        type: 'wire',
                        width: 4),
                  ],
                ),
              ],
            ),
            HierarchyNode(
              id: 'testbench.childB',
              name: 'childB',
              kind: HierarchyKind.instance,
              parentId: 'testbench',
              signals: [
                Signal(
                    id: 'testbench.childB.enable',
                    name: 'enable',
                    type: 'wire',
                    width: 1),
              ],
            ),
          ],
        ),
      );
    });

    test('searchSignalPaths with slash query finds dot-separated signal', () {
      // User types "childA/clk" — walker normalises to hierarchySeparator
      final results = vcdHierarchy.searchSignalPaths('childA/clk');
      expect(results, isNotEmpty);
      expect(results, contains('testbench/childA/clk'));
    });

    test('searchSignalPaths with slash query finds deep signal', () {
      final results = vcdHierarchy.searchSignalPaths('childA/sub/out');
      expect(results, isNotEmpty);
      expect(results, contains('testbench/childA/sub/out'));
    });

    test('searchSignals with slash query finds dot-separated signal', () {
      final results = vcdHierarchy.searchSignals('childA/clk');
      expect(results, isNotEmpty);
      expect(results.first.signal!.id, 'testbench.childA.clk');
    });

    test('searchModules with slash query finds dot-separated module', () {
      final results = vcdHierarchy.searchModules('childA');
      expect(results, isNotEmpty);
      expect(results.first.node.id, 'testbench.childA');
    });

    test('searchSignalPaths with dot query still works', () {
      // Dots in query are treated as separators too
      final results = vcdHierarchy.searchSignalPaths('childA.clk');
      expect(results, isNotEmpty);
      expect(results, contains('testbench/childA/clk'));
    });

    test('searchSignals with glob on dot-separated paths', () {
      // Glob wildcard should work across dot-separated IDs
      final results = vcdHierarchy.searchSignals('**/clk');
      expect(results.length, greaterThanOrEqualTo(2));
      final ids = results.map((r) => r.signal!.id).toSet();
      expect(ids, contains('testbench.clk'));
      expect(ids, contains('testbench.childA.clk'));
    });

    test('searchSignals with single segment on dot-separated paths', () {
      // Single segment search should use startsWith
      final results = vcdHierarchy.searchSignals('ena');
      expect(results, isNotEmpty);
      expect(results.first.signal!.id, 'testbench.childB.enable');
    });

    test('controller forSignals works with dot-separated hierarchy', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(vcdHierarchy)
            ..updateQuery('childA/clk');
      expect(ctrl.results, isNotEmpty);
      expect(ctrl.results.first.signal!.id, 'testbench.childA.clk');
    });
  });

  // ------------------------------------------------------------------
  // DevTools flow — hierarchy with local signal IDs
  // ------------------------------------------------------------------
  group('DevTools flow — local signal IDs → BaseHierarchyAdapter.fromTree', () {
    late BaseHierarchyAdapter rohdHierarchy;
    late HierarchySearchController<SignalSearchResult> rohdSignalCtrl;
    late HierarchySearchController<ModuleSearchResult> rohdModuleCtrl;

    setUp(() {
      // Build a tree with local signal IDs (not full paths) — this is the key
      // difference from the VCD path where IDs are full paths.
      final alu = HierarchyNode(
        id: 'Top/cpu/alu',
        name: 'alu',
        kind: HierarchyKind.module,
        parentId: 'Top/cpu',
        signals: [
          Port(
              id: 'a',
              name: 'a',
              type: 'wire',
              width: 16,
              direction: 'input',
              fullPath: 'Top/cpu/alu/a',
              scopeId: 'Top/cpu/alu'),
          Port(
              id: 'b',
              name: 'b',
              type: 'wire',
              width: 16,
              direction: 'input',
              fullPath: 'Top/cpu/alu/b',
              scopeId: 'Top/cpu/alu'),
          Port(
              id: 'result',
              name: 'result',
              type: 'wire',
              width: 16,
              direction: 'output',
              fullPath: 'Top/cpu/alu/result',
              scopeId: 'Top/cpu/alu'),
        ],
      );
      final cpu = HierarchyNode(
        id: 'Top/cpu',
        name: 'cpu',
        kind: HierarchyKind.module,
        parentId: 'Top',
        children: [alu],
        signals: [
          Port(
              id: 'data_in',
              name: 'data_in',
              type: 'wire',
              width: 8,
              direction: 'input',
              fullPath: 'Top/cpu/data_in',
              scopeId: 'Top/cpu'),
          Port(
              id: 'data_out',
              name: 'data_out',
              type: 'wire',
              width: 8,
              direction: 'output',
              fullPath: 'Top/cpu/data_out',
              scopeId: 'Top/cpu'),
        ],
      );
      final mem = HierarchyNode(
        id: 'Top/mem',
        name: 'mem',
        kind: HierarchyKind.module,
        parentId: 'Top',
        signals: [
          Port(
              id: 'addr',
              name: 'addr',
              type: 'wire',
              width: 32,
              direction: 'input',
              fullPath: 'Top/mem/addr',
              scopeId: 'Top/mem'),
        ],
      );
      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [cpu, mem],
        signals: [
          Port(
              id: 'clk',
              name: 'clk',
              type: 'wire',
              width: 1,
              direction: 'input',
              fullPath: 'Top/clk',
              scopeId: 'Top'),
          Port(
              id: 'rst',
              name: 'rst',
              type: 'wire',
              width: 1,
              direction: 'input',
              fullPath: 'Top/rst',
              scopeId: 'Top'),
        ],
      )..buildAddresses();
      rohdHierarchy = BaseHierarchyAdapter.fromTree(root);
      rohdSignalCtrl = HierarchySearchController.forSignals(rohdHierarchy);
      rohdModuleCtrl = HierarchySearchController.forModules(rohdHierarchy);
    });

    test('signal IDs are local (not full paths)', () {
      final rootSigs = rohdHierarchy.root.signals;
      final clk = rootSigs.firstWhere((s) => s.name == 'clk');
      expect(clk.id, 'clk');
      expect(clk.fullPath, 'Top/clk');
    });

    test('updateQuery finds signals despite local IDs', () {
      rohdSignalCtrl.updateQuery('clk');
      expect(rohdSignalCtrl.hasResults, isTrue);
      expect(rohdSignalCtrl.results.first.name, 'clk');
    });

    test('signalByAddress works with full path', () {
      final addr =
          HierarchyAddress.tryFromPathname('Top/clk', rohdHierarchy.root);
      final result = rohdHierarchy.signalByAddress(addr!);
      expect(result, isNotNull);
      expect(result!.name, 'clk');
    });

    test('signalByAddress works with nested path', () {
      final addr =
          HierarchyAddress.tryFromPathname('Top/cpu/alu/a', rohdHierarchy.root);
      final result = rohdHierarchy.signalByAddress(addr!);
      expect(result, isNotNull);
      expect(result!.name, 'a');
    });

    test('path-based search narrows to module', () {
      rohdSignalCtrl.updateQuery('cpu/data');
      expect(rohdSignalCtrl.hasResults, isTrue);
      final names = rohdSignalCtrl.results.map((r) => r.name).toSet();
      expect(names, containsAll(['data_in', 'data_out']));
    });

    test('glob search works', () {
      rohdSignalCtrl.updateQuery('**/a');
      expect(rohdSignalCtrl.hasResults, isTrue);
      final names = rohdSignalCtrl.results.map((r) => r.name).toSet();
      expect(names, contains('a'));
    });

    test('module search works', () {
      rohdModuleCtrl.updateQuery('alu');
      expect(rohdModuleCtrl.hasResults, isTrue);
      expect(rohdModuleCtrl.results.first.node.name, 'alu');
    });

    test('search results match VCD-style tree results', () {
      // The SAME queries should produce the same signal NAMES as
      // the manually-built tree (VCD path), even though signal IDs differ.
      rohdSignalCtrl.updateQuery('data');
      final rohdNames = rohdSignalCtrl.results.map((r) => r.name).toSet();

      signalCtrl.updateQuery('data');
      final vcdNames = signalCtrl.results.map((r) => r.name).toSet();

      expect(rohdNames, vcdNames,
          reason: 'Same query should find same signals regardless of source');
    });
  });
}
