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
// netlist JSON (NetlistHierarchyAdapter), or any other source.

import 'dart:convert';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Concrete subclass that does NOT set root, so we can test the
/// StateError thrown by uninitialized access.
class _UnsetAdapter extends BaseHierarchyAdapter {}

/// Resolve a pathname to a [SignalOccurrence] via
/// [OccurrenceAddress.tryFromPathname].
SignalOccurrence? _resolve(HierarchyService svc, String path) {
  final addr = OccurrenceAddress.tryFromPathname(path, svc.root);
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
      HierarchyOccurrence(
        name: 'Abcd',
        signals: [
          SignalOccurrence(name: 'clk', width: 1),
          SignalOccurrence(name: 'resetn', width: 1),
          SignalOccurrence(name: 'arvalid_s', width: 1),
        ],
        children: [
          HierarchyOccurrence(
            name: 'lab',
            signals: [
              SignalOccurrence(name: 'clk', width: 1),
              SignalOccurrence(name: 'reset', width: 1),
              SignalOccurrence(name: 'fromUpstream_request__st', width: 64),
            ],
            children: [
              HierarchyOccurrence(
                name: 'cam',
                signals: [
                  SignalOccurrence(name: 'hit', width: 1),
                  SignalOccurrence(name: 'entry', width: 32),
                ],
              ),
            ],
          ),
        ],
      ),
    );

/// Netlist JSON-style: flat-map adapter (like what DevTools/schematic viewer
/// builds from ROHD inspector JSON or netlist JSON).
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
      final vcdNodes = vcdService
          .searchOccurrences('lab')
          .map((r) => r.occurrence.name)
          .toSet();
      final jsonNodes = jsonService
          .searchOccurrences('lab')
          .map((r) => r.occurrence.name)
          .toSet();
      expect(vcdNodes, isNotEmpty);
      expect(vcdNodes, jsonNodes);
    });

    test('searchModules nested — same module names', () {
      final vcdNodes = vcdService
          .searchOccurrences('cam')
          .map((r) => r.occurrence.name)
          .toSet();
      final jsonNodes = jsonService
          .searchOccurrences('cam')
          .map((r) => r.occurrence.name)
          .toSet();
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

  group('BaseHierarchyAdapter.root', () {
    test('throws StateError when root is not set', () {
      final adapter = _UnsetAdapter();
      expect(() => adapter.root, throwsStateError);
    });
  });
}
