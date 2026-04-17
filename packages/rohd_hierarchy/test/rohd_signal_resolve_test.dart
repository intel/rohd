// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_signal_resolve_test.dart
// Tests for resolving ROHD dot-separated signal IDs.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  late HierarchyNode root;
  late BaseHierarchyAdapter adapter;

  setUpAll(() {
    root = HierarchyNode(
      id: 'abcd',
      name: 'abcd',
      kind: HierarchyKind.module,
      signals: [
        Port(
            id: 'abcd.clk',
            name: 'clk',
            type: 'wire',
            width: 1,
            direction: 'input'),
        Port(
            id: 'abcd.resetn',
            name: 'resetn',
            type: 'wire',
            width: 1,
            direction: 'input'),
        Port(
            id: 'abcd.arvalid_s',
            name: 'arvalid_s',
            type: 'wire',
            width: 1,
            direction: 'input'),
      ],
      children: [
        HierarchyNode(
          id: 'abcd.sub',
          name: 'sub',
          kind: HierarchyKind.module,
          parentId: 'abcd',
          signals: [
            Port(
                id: 'abcd.sub.data',
                name: 'data',
                type: 'wire',
                width: 8,
                direction: 'output'),
          ],
        ),
      ],
    );

    adapter = BaseHierarchyAdapter.fromTree(root);
    root.buildAddresses();
  });

  Signal? resolve(String dotPath) {
    final addr = HierarchyAddress.tryFromPathname(dotPath, root);
    if (addr == null) {
      return null;
    }
    return adapter.signalByAddress(addr);
  }

  group('findSignalById resolves ROHD dot-separated signal IDs', () {
    test('resolves top-level clk', () {
      final sig = resolve('abcd.clk');
      expect(sig, isNotNull);
      expect(sig!.id, 'abcd.clk');
    });

    test('resolves top-level resetn', () {
      final sig = resolve('abcd.resetn');
      expect(sig, isNotNull);
      expect(sig!.id, 'abcd.resetn');
    });

    test('resolves top-level arvalid_s', () {
      final sig = resolve('abcd.arvalid_s');
      expect(sig, isNotNull);
      expect(sig!.id, 'abcd.arvalid_s');
    });

    test('resolves nested sub.data', () {
      final sig = resolve('abcd.sub.data');
      expect(sig, isNotNull);
      expect(sig!.id, 'abcd.sub.data');
    });
  });
}
