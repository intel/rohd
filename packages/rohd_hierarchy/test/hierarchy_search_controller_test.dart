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
HierarchyOccurrence _buildTestTree() => HierarchyOccurrence(
      name: 'Top',
      signals: [
        SignalOccurrence(name: 'clk', width: 1),
        SignalOccurrence(name: 'rst', width: 1),
      ],
      children: [
        HierarchyOccurrence(
          name: 'cpu',
          signals: [
            SignalOccurrence(name: 'data_in', width: 8),
            SignalOccurrence(name: 'data_out', width: 8),
          ],
          children: [
            HierarchyOccurrence(
              name: 'alu',
              signals: [
                SignalOccurrence(name: 'a', width: 16),
                SignalOccurrence(name: 'b', width: 16),
                SignalOccurrence(name: 'result', width: 16),
              ],
            ),
          ],
        ),
        HierarchyOccurrence(
          name: 'mem',
          signals: [
            SignalOccurrence(name: 'addr', width: 32),
          ],
        ),
      ],
    );

void main() {
  late BaseHierarchyAdapter hierarchy;
  late HierarchySearchController<SignalSearchResult> signalCtrl;
  late HierarchySearchController<OccurrenceSearchResult> moduleCtrl;

  setUp(() {
    hierarchy = BaseHierarchyAdapter.fromTree(_buildTestTree());
    signalCtrl = HierarchySearchController.forSignals(hierarchy);
    moduleCtrl = HierarchySearchController.forOccurrences(hierarchy);
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
      expect(moduleCtrl.results.first.occurrence.name, 'cpu');
    });

    test('finds nested modules', () {
      moduleCtrl.updateQuery('alu');
      expect(moduleCtrl.hasResults, isTrue);
      expect(moduleCtrl.results.first.occurrence.name, 'alu');
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
        HierarchyOccurrence(
          name: 'testbench',
          signals: [
            SignalOccurrence(name: 'clk', width: 1),
            SignalOccurrence(name: 'rst', width: 1),
          ],
          children: [
            HierarchyOccurrence(
              name: 'childA',
              signals: [
                SignalOccurrence(name: 'clk', width: 1),
                SignalOccurrence(name: 'data', width: 8),
              ],
              children: [
                HierarchyOccurrence(
                  name: 'sub',
                  signals: [
                    SignalOccurrence(name: 'out', width: 4),
                  ],
                ),
              ],
            ),
            HierarchyOccurrence(
              name: 'childB',
              signals: [
                SignalOccurrence(name: 'enable', width: 1),
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
      expect(results.first.signal!.path(), 'testbench/childA/clk');
    });

    test('searchModules with slash query finds dot-separated module', () {
      final results = vcdHierarchy.searchOccurrences('childA');
      expect(results, isNotEmpty);
      expect(results.first.occurrence.path(), 'testbench/childA');
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
      final ids = results.map((r) => r.signal!.path()).toSet();
      expect(ids, contains('testbench/clk'));
      expect(ids, contains('testbench/childA/clk'));
    });

    test('searchSignals with single segment on dot-separated paths', () {
      // Single segment search should use startsWith
      final results = vcdHierarchy.searchSignals('ena');
      expect(results, isNotEmpty);
      expect(results.first.signal!.path(), 'testbench/childB/enable');
    });

    test('controller forSignals works with dot-separated hierarchy', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(vcdHierarchy)
            ..updateQuery('childA/clk');
      expect(ctrl.results, isNotEmpty);
      expect(ctrl.results.first.signal!.path(), 'testbench/childA/clk');
    });
  });

  // ------------------------------------------------------------------
  // DevTools flow — hierarchy with local signal IDs
  // ------------------------------------------------------------------
  group('DevTools flow — local signal IDs → BaseHierarchyAdapter.fromTree', () {
    late BaseHierarchyAdapter rohdHierarchy;
    late HierarchySearchController<SignalSearchResult> rohdSignalCtrl;
    late HierarchySearchController<OccurrenceSearchResult> rohdModuleCtrl;

    setUp(() {
      // Build a tree with local signal IDs (not full paths) — this is the key
      // difference from the VCD path where IDs are full paths.
      final alu = HierarchyOccurrence(
        name: 'alu',
        signals: [
          SignalOccurrence(
            name: 'a',
            width: 16,
            direction: 'input',
          ),
          SignalOccurrence(
            name: 'b',
            width: 16,
            direction: 'input',
          ),
          SignalOccurrence(
            name: 'result',
            width: 16,
            direction: 'output',
          ),
        ],
      );
      final cpu = HierarchyOccurrence(
        name: 'cpu',
        children: [alu],
        signals: [
          SignalOccurrence(
            name: 'data_in',
            width: 8,
            direction: 'input',
          ),
          SignalOccurrence(
            name: 'data_out',
            width: 8,
            direction: 'output',
          ),
        ],
      );
      final mem = HierarchyOccurrence(
        name: 'mem',
        signals: [
          SignalOccurrence(
            name: 'addr',
            width: 32,
            direction: 'input',
          ),
        ],
      );
      final root = HierarchyOccurrence(
        name: 'Top',
        children: [cpu, mem],
        signals: [
          SignalOccurrence(
            name: 'clk',
            width: 1,
            direction: 'input',
          ),
          SignalOccurrence(
            name: 'rst',
            width: 1,
            direction: 'input',
          ),
        ],
      )..buildAddresses();
      rohdHierarchy = BaseHierarchyAdapter.fromTree(root);
      rohdSignalCtrl = HierarchySearchController.forSignals(rohdHierarchy);
      rohdModuleCtrl = HierarchySearchController.forOccurrences(rohdHierarchy);
    });

    test('signal IDs are local (not full paths)', () {
      final rootSigs = rohdHierarchy.root.signals;
      final clk = rootSigs.firstWhere((s) => s.name == 'clk');
      expect(clk.name, 'clk');
      expect(clk.path(), 'Top/clk');
    });

    test('updateQuery finds signals despite local IDs', () {
      rohdSignalCtrl.updateQuery('clk');
      expect(rohdSignalCtrl.hasResults, isTrue);
      expect(rohdSignalCtrl.results.first.name, 'clk');
    });

    test('signalByAddress works with full path', () {
      final addr =
          OccurrenceAddress.tryFromPathname('Top/clk', rohdHierarchy.root);
      final result = rohdHierarchy.signalByAddress(addr!);
      expect(result, isNotNull);
      expect(result!.name, 'clk');
    });

    test('signalByAddress works with nested path', () {
      final addr = OccurrenceAddress.tryFromPathname(
          'Top/cpu/alu/a', rohdHierarchy.root);
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
      expect(rohdModuleCtrl.results.first.occurrence.name, 'alu');
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
