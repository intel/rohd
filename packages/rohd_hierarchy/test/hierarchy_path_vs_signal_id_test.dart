// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_path_vs_signal_id_test.dart
// Verifies that the canonical signal identity (hierarchyPath) and the
// search result path (signalId) are handled correctly across VCD
// (dot-separated) and ROHD (slash-separated) hierarchies.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('hierarchyPath vs signalId — VCD (dot-separated)', () {
    late BaseHierarchyAdapter adapter;

    setUp(() {
      final root = HierarchyNode(
        id: 'abcd',
        name: 'abcd',
        kind: HierarchyKind.module,
        signals: [
          Port(
            id: 'abcd.clk',
            name: 'clk',
            type: 'wire',
            width: 1,
            direction: 'input',
            fullPath: 'abcd.clk',
          ),
          Port(
            id: 'abcd.arvalid_s',
            name: 'arvalid_s',
            type: 'wire',
            width: 1,
            direction: 'input',
            fullPath: 'abcd.arvalid_s',
          ),
        ],
        children: [
          HierarchyNode(
            id: 'abcd.lab',
            name: 'lab',
            kind: HierarchyKind.module,
            parentId: 'abcd',
            signals: [
              Port(
                id: 'abcd.lab.clk',
                name: 'clk',
                type: 'wire',
                width: 1,
                direction: 'input',
                fullPath: 'abcd.lab.clk',
              ),
              Port(
                id: 'abcd.lab.data',
                name: 'data',
                type: 'wire',
                width: 8,
                direction: 'output',
                fullPath: 'abcd.lab.data',
              ),
            ],
          ),
        ],
      )..buildAddresses();
      adapter = BaseHierarchyAdapter.fromTree(root);
    });

    Signal? resolve(String path) {
      final addr = HierarchyAddress.tryFromPathname(path, adapter.root);
      return addr != null ? adapter.signalByAddress(addr) : null;
    }

    test('resolves dot-separated IDs', () {
      final s = resolve('abcd.clk');
      expect(s, isNotNull);
      expect(s!.hierarchyPath, 'abcd.clk');
    });

    test('resolves slash-separated IDs', () {
      final s = resolve('abcd/clk');
      expect(s, isNotNull);
      expect(s!.hierarchyPath, 'abcd.clk');
    });

    test('resolves case-insensitively', () {
      final s = resolve('Abcd.CLK');
      expect(s, isNotNull);
      expect(s!.hierarchyPath, 'abcd.clk');
    });

    test('resolves nested dot-separated IDs', () {
      final s = resolve('abcd.lab.data');
      expect(s, isNotNull);
      expect(s!.hierarchyPath, 'abcd.lab.data');
    });

    test('resolves nested slash-separated IDs', () {
      final s = resolve('abcd/lab/data');
      expect(s, isNotNull);
      expect(s!.hierarchyPath, 'abcd.lab.data');
    });

    test('searchSignals returns result with signal.hierarchyPath preserved',
        () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      // Every result should have a non-null signal
      for (final r in results) {
        expect(r.signal, isNotNull,
            reason: 'Signal should be resolved for "${r.signalId}"');
      }
      // The signal's hierarchyPath should be dot-separated (VCD format)
      final clkResult = results.firstWhere(
          (r) => r.path.last == 'clk' && r.path.length == 2); // root-level clk
      expect(clkResult.signal!.hierarchyPath, 'abcd.clk');
    });

    test('searchSignals signalId is walker-built (slash) path', () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      // signalId from the walker uses slash separator
      final clkResult =
          results.firstWhere((r) => r.path.last == 'clk' && r.path.length == 2);
      expect(clkResult.signalId, 'abcd/clk');
    });

    test(
        'signal selected from search has correct '
        'hierarchyPath for waveform lookup', () {
      final results = adapter.searchSignals('clk');
      final result = results.first;

      // When result.signal is non-null, use it directly
      // Its hierarchyPath is the canonical key for waveform lookup
      expect(result.signal, isNotNull);
      expect(result.signal!.hierarchyPath, startsWith('abcd.'));

      // The search signalId is slash-separated (different!)
      expect(result.signalId, contains('/'));

      // These are different representations of the same signal
      // hierarchyPath: for waveform data lookup (preserves original format)
      // signalId: for display (walker-built, always slash-separated)
    });

    test('searchSignalsRegex returns result with signal resolved', () {
      final results = adapter.searchSignalsRegex('**/clk');
      expect(results.length, greaterThanOrEqualTo(2));
      for (final r in results) {
        expect(r.signal, isNotNull,
            reason: 'Signal should be resolved for "${r.signalId}"');
        // hierarchyPath preserves the original dot format
        expect(r.signal!.hierarchyPath, contains('.'));
      }
    });
  });

  group('hierarchyPath vs signalId — ROHD (slash-separated)', () {
    late BaseHierarchyAdapter adapter;

    setUp(() {
      adapter = BaseHierarchyAdapter.fromTree(
        HierarchyNode(
          id: 'Top',
          name: 'Top',
          kind: HierarchyKind.module,
          signals: [
            Signal(id: 'Top/clk', name: 'clk', type: 'wire', width: 1),
          ],
          children: [
            HierarchyNode(
              id: 'Top/cpu',
              name: 'cpu',
              kind: HierarchyKind.instance,
              parentId: 'Top',
              signals: [
                Signal(
                  id: 'Top/cpu/data_out',
                  name: 'data_out',
                  type: 'wire',
                  width: 8,
                ),
              ],
            ),
          ],
        ),
      );
    });

    test('ROHD signals: hierarchyPath matches signalId (both slash)', () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      final r = results.first;
      // For ROHD, signal.id uses slash separator, no fullPath set
      // So hierarchyPath = id = 'Top/clk'
      // And signalId (walker) = 'Top/clk'
      // They match!
      expect(r.signal!.hierarchyPath, r.signalId);
    });
  });
}
