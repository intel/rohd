// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// coverage_gaps_test.dart
// Tests for API surface not covered by other test files:
//   - BaseHierarchyAdapter.root StateError on uninitialized access
//   - SignalOccurrence as port
//   - HierarchyOccurrence.parent
//   - SignalOccurrence.value
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Concrete subclass that does NOT set root, so we can test the
/// StateError thrown by uninitialized access.
class _UnsetAdapter extends BaseHierarchyAdapter {}

void main() {
  group('BaseHierarchyAdapter.root', () {
    test('throws StateError when root is not set', () {
      final adapter = _UnsetAdapter();
      expect(() => adapter.root, throwsStateError);
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

  group('HierarchyOccurrence.parent', () {
    test('parent is null for root', () {
      final root = HierarchyOccurrence(name: 'Top')..buildAddresses();
      expect(root.parent, isNull);
    });

    test('parent is set for child nodes after buildAddresses', () {
      final child = HierarchyOccurrence(name: 'sub');
      final root = HierarchyOccurrence(name: 'Top', children: [child])
        ..buildAddresses();
      expect(child.parent, same(root));
      expect(child.path(), 'Top/sub');
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

  group('HierarchyOccurrence.definition', () {
    test('type is null when not provided', () {
      final n = HierarchyOccurrence(name: 'a');
      expect(n.definition, isNull);
    });

    test('type is stored when provided', () {
      final n = HierarchyOccurrence(name: 'a', definition: 'Counter');
      expect(n.definition, 'Counter');
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

  group('isPrimitive on nodes', () {
    test('default isPrimitive is false', () {
      final n = HierarchyOccurrence(name: 'sub');
      expect(n.isPrimitive, isFalse);
    });
  });
}
