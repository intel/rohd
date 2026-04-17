// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_address_test.dart
// Unit tests for HierarchyAddress class.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('HierarchyAddress', () {
    test('child() appends module index', () {
      final addr = HierarchyAddress.root.child(0).child(2).child(4);
      expect(addr.path, equals([0, 2, 4]));
    });

    test('signal() appends signal index', () {
      final addr = const HierarchyAddress([0, 1]).signal(5);
      expect(addr.path, equals([0, 1, 5]));
    });

    test('equality and hashcode work correctly', () {
      const addr1 = HierarchyAddress([0, 2, 4]);
      const addr2 = HierarchyAddress([0, 2, 4]);
      const addr3 = HierarchyAddress([0, 2, 5]);

      expect(addr1, equals(addr2));
      expect(addr1.hashCode, equals(addr2.hashCode));
      expect(addr1, isNot(equals(addr3)));
      expect(addr1.hashCode, isNot(equals(addr3.hashCode)));
    });

    test('toString() returns debug string', () {
      expect(HierarchyAddress.root.toString(), equals('[ROOT]'));
      expect(const HierarchyAddress([0, 2, 4]).toString(), equals('[0.2.4]'));
    });

    test('toDotString() returns dot-separated path', () {
      expect(HierarchyAddress.root.toDotString(), equals(''));
      expect(const HierarchyAddress([0]).toDotString(), equals('0'));
      expect(const HierarchyAddress([0, 2, 4]).toDotString(), equals('0.2.4'));
      expect(const HierarchyAddress([10, 200]).toDotString(), equals('10.200'));
    });

    test('fromDotString() parses dot-separated path', () {
      expect(HierarchyAddress.fromDotString(''), equals(HierarchyAddress.root));
      expect(HierarchyAddress.fromDotString('0'),
          equals(const HierarchyAddress([0])));
      expect(HierarchyAddress.fromDotString('0.2.4'),
          equals(const HierarchyAddress([0, 2, 4])));
      expect(HierarchyAddress.fromDotString('10.200'),
          equals(const HierarchyAddress([10, 200])));
    });

    test('toDotString/fromDotString round-trip', () {
      final testCases = [
        HierarchyAddress.root,
        const HierarchyAddress([0]),
        const HierarchyAddress([5, 10, 15]),
        const HierarchyAddress([0, 0, 0]),
        const HierarchyAddress([255]),
        const HierarchyAddress([0, 1, 2, 3, 4, 5]),
      ];
      for (final original in testCases) {
        final dot = original.toDotString();
        final restored = HierarchyAddress.fromDotString(dot);
        expect(restored, equals(original), reason: 'Failed for $original');
      }
    });
  });

  group('HierarchyAddress with HierarchyNode integration', () {
    late HierarchyNode root;

    setUp(() {
      // Build a simple tree structure
      final child0 = HierarchyNode(
        id: 'child_0',
        name: 'child_0',
        kind: HierarchyKind.module,
        signals: [
          Signal(
            id: 'sig0',
            name: 'sig0',
            type: 'wire',
            width: 1,
            fullPath: 'root/child_0/sig0',
            scopeId: 'root/child_0',
          ),
          Signal(
            id: 'sig1',
            name: 'sig1',
            type: 'wire',
            width: 8,
            fullPath: 'root/child_0/sig1',
            scopeId: 'root/child_0',
          ),
        ],
      );

      final grandchild = HierarchyNode(
        id: 'root/child_0/grandchild_0',
        name: 'grandchild_0',
        kind: HierarchyKind.module,
        signals: [
          Signal(
            id: 'sig0',
            name: 'sig0',
            type: 'wire',
            width: 1,
            fullPath: 'root/child_0/grandchild_0/sig0',
            scopeId: 'root/child_0/grandchild_0',
          ),
        ],
      );

      final child1 = HierarchyNode(
        id: 'child_1',
        name: 'child_1',
        kind: HierarchyKind.module,
        signals: [
          Signal(
            id: 'sig0',
            name: 'sig0',
            type: 'wire',
            width: 4,
            fullPath: 'root/child_1/sig0',
            scopeId: 'root/child_1',
          ),
        ],
      );

      child0.children.add(grandchild);

      root = HierarchyNode(
        id: 'root',
        name: 'root',
        kind: HierarchyKind.module,
        signals: [
          Signal(
            id: 'clk',
            name: 'clk',
            type: 'wire',
            width: 1,
            fullPath: 'root/clk',
            scopeId: 'root',
          ),
        ],
        children: [child0, child1],
      )
        // Build addresses for all nodes
        ..buildAddresses();
    });

    test('buildAddresses assigns address to root', () {
      expect(root.address, equals(HierarchyAddress.root));
    });

    test('buildAddresses assigns addresses to all nodes', () {
      expect(root.children[0].address, equals(const HierarchyAddress([0])));
      expect(root.children[1].address, equals(const HierarchyAddress([1])));
      expect(root.children[0].children[0].address,
          equals(const HierarchyAddress([0, 0])));
    });

    test('buildAddresses assigns addresses to all signals', () {
      // Root signals
      expect(root.signals[0].address, equals(const HierarchyAddress([0])));

      // Child signals
      expect(root.children[0].signals[0].address,
          equals(const HierarchyAddress([0, 0])));
      expect(root.children[0].signals[1].address,
          equals(const HierarchyAddress([0, 1])));

      // Grandchild signals
      expect(root.children[0].children[0].signals[0].address,
          equals(const HierarchyAddress([0, 0, 0])));
    });
  });
}
