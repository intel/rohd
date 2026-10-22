// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_search_flow_test.dart
// Tests that simulate the DevTools embedding flow with local signal IDs:
//   HierarchyNode tree → BaseHierarchyAdapter.fromTree → search
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// The test verifies that search works correctly with local signal IDs
// (as opposed to VCD-style full-path IDs), catching any assumption
// mismatches in the search engine.

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Build the test hierarchy tree directly, matching the structure
/// that would be produced from ROHD inspector JSON.
/// Signals have local IDs and full qualified paths.
HierarchyOccurrence _buildTestHierarchy() {
  final cam = HierarchyOccurrence(
    name: 'cam',
    signals: [
      SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'hit',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'entry',
        width: 32,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'match_out',
        width: 1,
        direction: 'output',
      ),
    ],
  );

  final lab = HierarchyOccurrence(
    name: 'lab',
    children: [cam],
    signals: [
      SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'reset',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'fromUpstream_request__st',
        width: 64,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'toUpstream_response__st',
        width: 64,
        direction: 'output',
      ),
    ],
  );

  final dmaEngine = HierarchyOccurrence(
    name: 'engine',
    signals: [
      SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'enable',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'data_in',
        width: 64,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'data_out',
        width: 64,
        direction: 'output',
      ),
      SignalOccurrence(
        name: 'done',
        width: 1,
        direction: 'output',
      ),
    ],
  );

  return HierarchyOccurrence(
    name: 'Abcd',
    children: [lab, dmaEngine],
    signals: [
      SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'resetn',
        width: 1,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'araddr_s',
        width: 32,
        direction: 'input',
      ),
      SignalOccurrence(
        name: 'rdata_s',
        width: 32,
        direction: 'output',
      ),
    ],
  );
}

void main() {
  late BaseHierarchyAdapter service;

  setUp(() {
    final root = _buildTestHierarchy()..buildAddresses();
    service = BaseHierarchyAdapter.fromTree(root);
  });

  group(
      'DevTools flow — local signal IDs '
      '→ BaseHierarchyAdapter.fromTree → search', () {
    // Basic search, address, glob, and controller behavior is covered by
    // hierarchy_search_controller_test, regex_search_test,
    // address_conversion_test, and module_search_test.
    //
    // This group focuses on what is unique to the DevTools local-ID flow:
    // search correctness when SignalOccurrence.name is a local name (not a full
    // path).

    test('search works with local signal IDs', () {
      // Plain prefix search still finds signals by name
      final results = service.searchSignals('clk');
      expect(results, isNotEmpty);
      expect(results.map((r) => r.name), everyElement('clk'));
      // Glob still works
      final globResults = service.searchSignals('**/entry');
      expect(globResults, isNotEmpty);
      expect(globResults.first.name, 'entry');
    });

    test('signalByAddress resolves despite local IDs', () {
      final addr =
          OccurrenceAddress.tryFromPathname('Abcd/lab/cam/hit', service.root);
      expect(addr, isNotNull);
      final hit = service.signalByAddress(addr!);
      expect(hit, isNotNull);
      expect(hit!.name, 'hit');
      expect(hit.name, 'hit'); // local, not full path
      expect(hit.path(), 'Abcd/lab/cam/hit');
    });

    test('searchModules works with local-ID tree', () {
      final results = service.searchOccurrences('cam');
      expect(results, isNotEmpty);
      expect(results.first.occurrence.name, 'cam');
    });
  });

  // ── SignalOccurrence ID format verification ──

  group('local signal ID format', () {
    test('signals have local IDs (not full paths)', () {
      final sigs = service.root.signals;
      final clk = sigs.firstWhere((s) => s.name == 'clk');
      // The signal id is the local name, not the full path
      expect(clk.name, 'clk');
      // But fullPath is the full qualified path
      expect(clk.path(), 'Abcd/clk');
    });

    test('local signal IDs do not break address resolution', () {
      final addr = OccurrenceAddress.tryFromPathname(
          'Abcd/lab/cam/match_out', service.root);
      expect(addr, isNotNull);
      final result = service.signalByAddress(addr!);
      expect(result, isNotNull);
      expect(result!.name, 'match_out');
      expect(result.name, 'match_out'); // local name
    });

    test('search results carry the correct signal object', () {
      final results = service.searchSignals('Abcd/rdata_s');
      expect(results, isNotEmpty);
      final r = results.first;
      expect(r.signal, isNotNull);
      expect(r.signal!.name, 'rdata_s'); // local name
      expect(r.signal!.path(), 'Abcd/rdata_s'); // full path
      expect(r.signal!.width, 32);
    });
  });
}
