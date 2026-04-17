// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// adapter_search_parity_test.dart
// Baseline tests verifying that search produces identical results
// regardless of which adapter populated the HierarchyService.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// This is the key contract: once a HierarchyService is built, callers
// cannot tell whether the data came from VCD (BaseHierarchyAdapter.fromTree),
// Yosys JSON (NetlistHierarchyAdapter), or any other source.

import 'dart:convert';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Resolve a pathname to a [Signal] via [HierarchyAddress.tryFromPathname].
Signal? _resolve(HierarchyService svc, String path) {
  final addr = HierarchyAddress.tryFromPathname(path, svc.root);
  if (addr == null) {
    return null;
  }
  return svc.signalByAddress(addr);
}

// ──────────────────────────────────────────────────────────────────────
// Build the SAME design via two different adapter paths
// ──────────────────────────────────────────────────────────────────────

/// VCD-style: HierarchyNode tree with children/signals populated inline.
/// This is what `wellen` produces when loading a VCD/FST file.
BaseHierarchyAdapter _buildVcdAdapter() => BaseHierarchyAdapter.fromTree(
      HierarchyNode(
        id: 'Abcd',
        name: 'Abcd',
        kind: HierarchyKind.module,
        signals: [
          Signal(id: 'Abcd/clk', name: 'clk', type: 'wire', width: 1),
          Signal(id: 'Abcd/resetn', name: 'resetn', type: 'wire', width: 1),
          Signal(
              id: 'Abcd/arvalid_s', name: 'arvalid_s', type: 'wire', width: 1),
        ],
        children: [
          HierarchyNode(
            id: 'Abcd/lab',
            name: 'lab',
            kind: HierarchyKind.instance,
            parentId: 'Abcd',
            signals: [
              Signal(id: 'Abcd/lab/clk', name: 'clk', type: 'wire', width: 1),
              Signal(
                  id: 'Abcd/lab/reset', name: 'reset', type: 'wire', width: 1),
              Signal(
                  id: 'Abcd/lab/fromUpstream_request__st',
                  name: 'fromUpstream_request__st',
                  type: 'wire',
                  width: 64),
            ],
            children: [
              HierarchyNode(
                id: 'Abcd/lab/cam',
                name: 'cam',
                kind: HierarchyKind.instance,
                parentId: 'Abcd/lab',
                signals: [
                  Signal(
                      id: 'Abcd/lab/cam/hit',
                      name: 'hit',
                      type: 'wire',
                      width: 1),
                  Signal(
                      id: 'Abcd/lab/cam/entry',
                      name: 'entry',
                      type: 'wire',
                      width: 32),
                ],
              ),
            ],
          ),
        ],
      ),
    );

/// Yosys JSON-style: flat-map adapter (like what DevTools/schematic viewer
/// builds from ROHD inspector JSON or Yosys JSON).
/// Children and signals live in the adapter's flat maps, NOT inside
/// the HierarchyNode objects.
NetlistHierarchyAdapter _buildJsonAdapter() =>
    NetlistHierarchyAdapter.fromJson(jsonEncode({
      'modules': {
        'Abcd': {
          'attributes': {'top': 1},
          'ports': {
            'clk': {
              'direction': 'input',
              'bits': [1]
            },
            'resetn': {
              'direction': 'input',
              'bits': [2]
            },
            'arvalid_s': {
              'direction': 'input',
              'bits': [3]
            },
          },
          'netnames': <String, dynamic>{},
          'cells': {
            'lab': {
              'type': 'Lab',
              'connections': <String, dynamic>{},
            },
          },
        },
        'Lab': {
          'ports': {
            'clk': {
              'direction': 'input',
              'bits': [10]
            },
            'reset': {
              'direction': 'input',
              'bits': [11]
            },
            'fromUpstream_request__st': {
              'direction': 'input',
              'bits': List.generate(64, (i) => 100 + i)
            },
          },
          'netnames': <String, dynamic>{},
          'cells': {
            'cam': {
              'type': 'Cam',
              'connections': <String, dynamic>{},
            },
          },
        },
        'Cam': {
          'ports': {
            'hit': {
              'direction': 'input',
              'bits': [200]
            },
            'entry': {
              'direction': 'input',
              'bits': List.generate(32, (i) => 300 + i)
            },
          },
          'netnames': <String, dynamic>{},
          'cells': <String, dynamic>{},
        },
      },
    }));

void main() {
  late HierarchyService vcdService;
  late HierarchyService jsonService;

  setUp(() {
    vcdService = _buildVcdAdapter();
    jsonService = _buildJsonAdapter();
  });

  // ── The two services must be interchangeable for all search ops ──
  // Case-insensitivity, dot separators, controller state, and
  // search semantics are covered in address_conversion_test,
  // hierarchy_search_controller_test, and regex_search_test.
  // This file focuses exclusively on *parity* between adapters.

  group('Adapter search parity — both sources produce same results', () {
    test('root name matches', () {
      expect(vcdService.root.name, 'Abcd');
      expect(jsonService.root.name, 'Abcd');
    });

    test('root.children returns same module names', () {
      final vcdChildren = vcdService.root.children.map((c) => c.name).toSet();
      final jsonChildren = jsonService.root.children.map((c) => c.name).toSet();
      expect(vcdChildren, jsonChildren);
    });

    test('root.signals returns same signal names at root', () {
      final vcdSigs = vcdService.root.signals.map((s) => s.name).toSet();
      final jsonSigs = jsonService.root.signals.map((s) => s.name).toSet();
      expect(vcdSigs, jsonSigs);
    });

    test('nested node signals() returns same signal names', () {
      final vcdLab = vcdService.root.children.first;
      final jsonLab = jsonService.root.children.first;
      final vcdSigs = vcdLab.signals.map((s) => s.name).toSet();
      final jsonSigs = jsonLab.signals.map((s) => s.name).toSet();
      expect(vcdSigs, jsonSigs);
    });

    test('signalByAddress works on both — top level', () {
      final vcdClk = _resolve(vcdService, 'Abcd/clk');
      final jsonClk = _resolve(jsonService, 'Abcd/clk');
      expect(vcdClk, isNotNull, reason: 'VCD: Abcd/clk');
      expect(jsonClk, isNotNull, reason: 'JSON: Abcd/clk');
      expect(vcdClk!.name, 'clk');
      expect(jsonClk!.name, 'clk');
    });

    test('signalByAddress works on both — nested', () {
      final vcdHit = _resolve(vcdService, 'Abcd/lab/cam/hit');
      final jsonHit = _resolve(jsonService, 'Abcd/lab/cam/hit');
      expect(vcdHit, isNotNull, reason: 'VCD: Abcd/lab/cam/hit');
      expect(jsonHit, isNotNull, reason: 'JSON: Abcd/lab/cam/hit');
      expect(vcdHit!.name, 'hit');
      expect(jsonHit!.name, 'hit');
    });

    test('searchSignals plain query — same result names', () {
      final vcdResults =
          vcdService.searchSignals('clk').map((r) => r.name).toSet();
      final jsonResults =
          jsonService.searchSignals('clk').map((r) => r.name).toSet();
      expect(vcdResults, isNotEmpty);
      expect(vcdResults, jsonResults);
    });

    test('searchSignals glob query — same result names', () {
      final vcdResults =
          vcdService.searchSignals('**/clk').map((r) => r.name).toSet();
      final jsonResults =
          jsonService.searchSignals('**/clk').map((r) => r.name).toSet();
      expect(vcdResults, isNotEmpty);
      expect(vcdResults, jsonResults);
    });

    test('searchSignals path query — same result names', () {
      final vcdResults =
          vcdService.searchSignals('lab/clk').map((r) => r.name).toSet();
      final jsonResults =
          jsonService.searchSignals('lab/clk').map((r) => r.name).toSet();
      expect(vcdResults, isNotEmpty);
      expect(vcdResults, jsonResults);
    });

    test('searchModules — same module names', () {
      final vcdNodes =
          vcdService.searchModules('lab').map((r) => r.node.name).toSet();
      final jsonNodes =
          jsonService.searchModules('lab').map((r) => r.node.name).toSet();
      expect(vcdNodes, isNotEmpty);
      expect(vcdNodes, jsonNodes);
    });

    test('searchModules nested — same module names', () {
      final vcdNodes =
          vcdService.searchModules('cam').map((r) => r.node.name).toSet();
      final jsonNodes =
          jsonService.searchModules('cam').map((r) => r.node.name).toSet();
      expect(vcdNodes, isNotEmpty);
      expect(vcdNodes, jsonNodes);
    });
  });

  // ── Verify the external-hierarchy handoff works ──
  // Individual search/address semantics are covered elsewhere.
  // This group tests the adapter re-wrapping contract.

  group('External hierarchy flow (simulates DevTools → wave viewer)', () {
    test('BaseHierarchyAdapter.fromTree produces identical search results', () {
      final rewrapped = BaseHierarchyAdapter.fromTree(jsonService.root);

      final results = rewrapped.searchSignals('clk');
      expect(results, isNotEmpty);
      expect(
        results.map((r) => r.name).toSet(),
        jsonService.searchSignals('clk').map((r) => r.name).toSet(),
      );
    });

    test('BaseHierarchyAdapter.fromTree preserves signalByAddress', () {
      final rewrapped = BaseHierarchyAdapter.fromTree(jsonService.root);

      final hit = _resolve(rewrapped, 'Abcd/lab/cam/hit');
      expect(hit, isNotNull);
      expect(hit!.name, 'hit');
    });
  });
}
