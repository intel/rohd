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
HierarchyNode _buildTestHierarchy() {
  final cam = HierarchyNode(
    id: 'Abcd/lab/cam',
    name: 'cam',
    kind: HierarchyKind.module,
    parentId: 'Abcd/lab',
    signals: [
      Port(
          id: 'clk',
          name: 'clk',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/lab/cam/clk',
          scopeId: 'Abcd/lab/cam'),
      Port(
          id: 'hit',
          name: 'hit',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/lab/cam/hit',
          scopeId: 'Abcd/lab/cam'),
      Port(
          id: 'entry',
          name: 'entry',
          type: 'wire',
          width: 32,
          direction: 'input',
          fullPath: 'Abcd/lab/cam/entry',
          scopeId: 'Abcd/lab/cam'),
      Port(
          id: 'match_out',
          name: 'match_out',
          type: 'wire',
          width: 1,
          direction: 'output',
          fullPath: 'Abcd/lab/cam/match_out',
          scopeId: 'Abcd/lab/cam'),
    ],
  );

  final lab = HierarchyNode(
    id: 'Abcd/lab',
    name: 'lab',
    kind: HierarchyKind.module,
    parentId: 'Abcd',
    children: [cam],
    signals: [
      Port(
          id: 'clk',
          name: 'clk',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/lab/clk',
          scopeId: 'Abcd/lab'),
      Port(
          id: 'reset',
          name: 'reset',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/lab/reset',
          scopeId: 'Abcd/lab'),
      Port(
          id: 'fromUpstream_request__st',
          name: 'fromUpstream_request__st',
          type: 'wire',
          width: 64,
          direction: 'input',
          fullPath: 'Abcd/lab/fromUpstream_request__st',
          scopeId: 'Abcd/lab'),
      Port(
          id: 'toUpstream_response__st',
          name: 'toUpstream_response__st',
          type: 'wire',
          width: 64,
          direction: 'output',
          fullPath: 'Abcd/lab/toUpstream_response__st',
          scopeId: 'Abcd/lab'),
    ],
  );

  final dmaEngine = HierarchyNode(
    id: 'Abcd/engine',
    name: 'engine',
    kind: HierarchyKind.module,
    parentId: 'Abcd',
    signals: [
      Port(
          id: 'clk',
          name: 'clk',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/engine/clk',
          scopeId: 'Abcd/engine'),
      Port(
          id: 'enable',
          name: 'enable',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/engine/enable',
          scopeId: 'Abcd/engine'),
      Port(
          id: 'data_in',
          name: 'data_in',
          type: 'wire',
          width: 64,
          direction: 'input',
          fullPath: 'Abcd/engine/data_in',
          scopeId: 'Abcd/engine'),
      Port(
          id: 'data_out',
          name: 'data_out',
          type: 'wire',
          width: 64,
          direction: 'output',
          fullPath: 'Abcd/engine/data_out',
          scopeId: 'Abcd/engine'),
      Port(
          id: 'done',
          name: 'done',
          type: 'wire',
          width: 1,
          direction: 'output',
          fullPath: 'Abcd/engine/done',
          scopeId: 'Abcd/engine'),
    ],
  );

  return HierarchyNode(
    id: 'Abcd',
    name: 'Abcd',
    kind: HierarchyKind.module,
    children: [lab, dmaEngine],
    signals: [
      Port(
          id: 'clk',
          name: 'clk',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/clk',
          scopeId: 'Abcd'),
      Port(
          id: 'resetn',
          name: 'resetn',
          type: 'wire',
          width: 1,
          direction: 'input',
          fullPath: 'Abcd/resetn',
          scopeId: 'Abcd'),
      Port(
          id: 'araddr_s',
          name: 'araddr_s',
          type: 'wire',
          width: 32,
          direction: 'input',
          fullPath: 'Abcd/araddr_s',
          scopeId: 'Abcd'),
      Port(
          id: 'rdata_s',
          name: 'rdata_s',
          type: 'wire',
          width: 32,
          direction: 'output',
          fullPath: 'Abcd/rdata_s',
          scopeId: 'Abcd'),
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
    // search correctness when Signal.id is a local name (not a full path).

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
          HierarchyAddress.tryFromPathname('Abcd/lab/cam/hit', service.root);
      expect(addr, isNotNull);
      final hit = service.signalByAddress(addr!);
      expect(hit, isNotNull);
      expect(hit!.name, 'hit');
      expect(hit.id, 'hit'); // local, not full path
      expect(hit.fullPath, 'Abcd/lab/cam/hit');
    });

    test('searchModules works with local-ID tree', () {
      final results = service.searchModules('cam');
      expect(results, isNotEmpty);
      expect(results.first.node.name, 'cam');
    });
  });

  // ── Signal ID format verification ──

  group('local signal ID format', () {
    test('signals have local IDs (not full paths)', () {
      final sigs = service.root.signals;
      final clk = sigs.firstWhere((s) => s.name == 'clk');
      // The signal id is the local name, not the full path
      expect(clk.id, 'clk');
      // But fullPath is the full qualified path
      expect(clk.fullPath, 'Abcd/clk');
    });

    test('local signal IDs do not break address resolution', () {
      final addr = HierarchyAddress.tryFromPathname(
          'Abcd/lab/cam/match_out', service.root);
      expect(addr, isNotNull);
      final result = service.signalByAddress(addr!);
      expect(result, isNotNull);
      expect(result!.name, 'match_out');
      expect(result.id, 'match_out'); // local name
    });

    test('search results carry the correct signal object', () {
      final results = service.searchSignals('Abcd/rdata_s');
      expect(results, isNotEmpty);
      final r = results.first;
      expect(r.signal, isNotNull);
      expect(r.signal!.id, 'rdata_s'); // local name
      expect(r.signal!.fullPath, 'Abcd/rdata_s'); // full path
      expect(r.signal!.width, 32);
    });
  });
}
