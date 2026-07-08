// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_path_vs_signal_id_test.dart
// Verifies that signal.path(separator:) and search result signalId
// work correctly with different separators.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('signal.path() with separator', () {
    late BaseHierarchyAdapter adapter;

    setUp(() {
      final root = HierarchyOccurrence(
        name: 'abcd',
        signals: [
          SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
          SignalOccurrence(name: 'arvalid_s', width: 1, direction: 'input'),
        ],
        children: [
          HierarchyOccurrence(
            name: 'lab',
            signals: [
              SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
              SignalOccurrence(name: 'data', width: 8, direction: 'output'),
            ],
          ),
        ],
      )..buildAddresses();
      adapter = BaseHierarchyAdapter.fromTree(root);
    });

    SignalOccurrence? resolve(String path) {
      final addr = OccurrenceAddress.tryFromPathname(path, adapter.root);
      return addr != null ? adapter.signalByAddress(addr) : null;
    }

    test('resolves dot-separated IDs', () {
      final s = resolve('abcd.clk');
      expect(s, isNotNull);
      expect(s!.path(separator: '.'), 'abcd.clk');
    });

    test('resolves slash-separated IDs', () {
      final s = resolve('abcd/clk');
      expect(s, isNotNull);
      expect(s!.path(), 'abcd/clk');
    });

    test('resolves with exact case', () {
      final s = resolve('abcd.clk');
      expect(s, isNotNull);
      expect(s!.path(), 'abcd/clk');
    });

    test('resolves nested dot-separated IDs', () {
      final s = resolve('abcd.lab.data');
      expect(s, isNotNull);
      expect(s!.path(separator: '.'), 'abcd.lab.data');
    });

    test('resolves nested slash-separated IDs', () {
      final s = resolve('abcd/lab/data');
      expect(s, isNotNull);
      expect(s!.path(), 'abcd/lab/data');
    });

    test('searchSignals returns result with resolved signal', () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.signal, isNotNull,
            reason: 'SignalOccurrence should be resolved for "${r.signalId}"');
      }
      final clkResult =
          results.firstWhere((r) => r.path.last == 'clk' && r.path.length == 2);
      expect(clkResult.signal!.path(), 'abcd/clk');
      expect(clkResult.signal!.path(separator: '.'), 'abcd.clk');
    });

    test('searchSignals signalId is walker-built (slash) path', () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      final clkResult =
          results.firstWhere((r) => r.path.last == 'clk' && r.path.length == 2);
      expect(clkResult.signalId, 'abcd/clk');
    });

    test('signal.path() matches signalId with default separator', () {
      final results = adapter.searchSignals('clk');
      final result = results.first;
      expect(result.signal, isNotNull);
      expect(result.signal!.path(), result.signalId);
    });

    test('searchSignalsRegex returns result with signal resolved', () {
      final results = adapter.searchSignalsRegex('**/clk');
      expect(results.length, greaterThanOrEqualTo(2));
      for (final r in results) {
        expect(r.signal, isNotNull,
            reason: 'SignalOccurrence should be resolved for "${r.signalId}"');
        expect(r.signal!.path(), contains('/'));
      }
    });
  });

  group('ROHD slash-separated hierarchy', () {
    late BaseHierarchyAdapter adapter;

    setUp(() {
      final root = HierarchyOccurrence(
        name: 'Top',
        signals: [SignalOccurrence(name: 'clk', width: 1)],
        children: [
          HierarchyOccurrence(
            name: 'cpu',
            signals: [SignalOccurrence(name: 'data_out', width: 8)],
          ),
        ],
      )..buildAddresses();
      adapter = BaseHierarchyAdapter.fromTree(root);
    });

    test('ROHD signals: path() matches signalId (both slash)', () {
      final results = adapter.searchSignals('clk');
      expect(results, isNotEmpty);
      final r = results.first;
      expect(r.signal!.path(), r.signalId);
    });
  });

  group('SignalOccurrence as port', () {
    test('creates a port signal with defaults', () {
      final p = SignalOccurrence(name: 'clk', width: 1, direction: 'input');
      expect(p.name, 'clk');
      expect(p.direction, 'input');
      expect(p.width, 1);
      expect(p.isPort, isTrue);
      expect(p.isInput, isTrue);
    });

    test('creates a port signal with explicit overrides', () {
      final p = SignalOccurrence(
        name: 'data',
        direction: 'output',
        width: 32,
        isComputed: true,
      );
      HierarchyOccurrence(name: 'Top', signals: [p]).buildAddresses();
      expect(p.name, 'data');
      expect(p.width, 32);
      expect(p.direction, 'output');
      expect(p.path(), 'Top/data');
      expect(p.parent!.path(), 'Top');
      expect(p.isComputed, isTrue);
      expect(p.isOutput, isTrue);
    });
  });

  group('SignalOccurrence.value', () {
    test('value is null by default', () {
      final s = SignalOccurrence(name: 'a', width: 1);
      expect(s.value, isNull);
    });

    test('value stores the provided runtime value', () {
      final s = SignalOccurrence(name: 'a', width: 8, value: 'ff');
      expect(s.value, 'ff');
    });
  });

  group('SignalOccurrence.parent', () {
    test('parent is null before buildAddresses', () {
      final s = SignalOccurrence(name: 'a', width: 1);
      expect(s.parent, isNull);
    });

    test('parent is set after buildAddresses', () {
      final s = SignalOccurrence(name: 'a', width: 1);
      HierarchyOccurrence(
        name: 'Top',
        children: [
          HierarchyOccurrence(name: 'sub', signals: [s])
        ],
      ).buildAddresses();
      expect(s.parent!.path(), 'Top/sub');
    });
  });
}
