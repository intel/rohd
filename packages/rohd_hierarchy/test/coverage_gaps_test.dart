// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// coverage_gaps_test.dart
// Tests for API surface not covered by other test files:
//   - BaseHierarchyAdapter.root StateError on uninitialized access
//   - Port.simple factory
//   - HierarchyNode.parentId
//   - Signal.value
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

  group('Port.simple factory', () {
    test('creates a port with defaults', () {
      final p = Port.simple(name: 'clk', direction: 'input');
      expect(p.name, 'clk');
      expect(p.id, 'clk'); // defaults to name
      expect(p.direction, 'input');
      expect(p.width, 1);
      expect(p.type, 'wire');
      expect(p.isPort, isTrue);
      expect(p.isInput, isTrue);
    });

    test('creates a port with explicit overrides', () {
      final p = Port.simple(
        name: 'data',
        direction: 'output',
        width: 32,
        id: 'data_out',
        type: 'logic',
        fullPath: 'Top/data',
        scopeId: 'Top',
        isComputed: true,
      );
      expect(p.id, 'data_out');
      expect(p.name, 'data');
      expect(p.width, 32);
      expect(p.type, 'logic');
      expect(p.direction, 'output');
      expect(p.fullPath, 'Top/data');
      expect(p.scopeId, 'Top');
      expect(p.isComputed, isTrue);
      expect(p.isOutput, isTrue);
    });
  });

  group('HierarchyNode.parentId', () {
    test('parentId is null for root', () {
      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
      );
      expect(root.parentId, isNull);
    });

    test('parentId is set for child nodes', () {
      final child = HierarchyNode(
        id: 'Top/sub',
        name: 'sub',
        kind: HierarchyKind.instance,
        parentId: 'Top',
      );
      final root = HierarchyNode(
        id: 'Top',
        name: 'Top',
        kind: HierarchyKind.module,
        children: [child],
      );
      expect(root.children.first.parentId, 'Top');
    });
  });

  group('Signal.value', () {
    test('value is null by default', () {
      final s = Signal(id: 'a', name: 'a', type: 'wire', width: 1);
      expect(s.value, isNull);
    });

    test('value stores the provided runtime value', () {
      final s = Signal(
        id: 'a',
        name: 'a',
        type: 'wire',
        width: 8,
        value: 'ff',
      );
      expect(s.value, 'ff');
    });
  });

  group('HierarchyNode.type', () {
    test('type is null when not provided', () {
      final n = HierarchyNode(
        id: 'a',
        name: 'a',
        kind: HierarchyKind.module,
      );
      expect(n.type, isNull);
    });

    test('type is stored when provided', () {
      final n = HierarchyNode(
        id: 'a',
        name: 'a',
        kind: HierarchyKind.instance,
        type: 'Counter',
      );
      expect(n.type, 'Counter');
    });
  });

  group('Signal.scopeId', () {
    test('scopeId is null by default', () {
      final s = Signal(id: 'a', name: 'a', type: 'wire', width: 1);
      expect(s.scopeId, isNull);
    });

    test('scopeId is stored when provided', () {
      final s = Signal(
        id: 'a',
        name: 'a',
        type: 'wire',
        width: 1,
        scopeId: 'Top/sub',
      );
      expect(s.scopeId, 'Top/sub');
    });
  });

  group('HierarchyKind on instances', () {
    test('instance kind is reflected correctly', () {
      final n = HierarchyNode(
        id: 'Top/sub',
        name: 'sub',
        kind: HierarchyKind.instance,
      );
      expect(n.kind, HierarchyKind.instance);
    });
  });
}
