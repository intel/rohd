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
  late HierarchyOccurrence root;
  late BaseHierarchyAdapter adapter;

  setUpAll(() {
    root = HierarchyOccurrence(
      name: 'abcd',
      signals: [
        SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
        SignalOccurrence(name: 'resetn', width: 1, direction: 'input'),
        SignalOccurrence(name: 'arvalid_s', width: 1, direction: 'input'),
      ],
      children: [
        HierarchyOccurrence(
          name: 'sub',
          signals: [
            SignalOccurrence(name: 'data', width: 8, direction: 'output'),
          ],
        ),
      ],
    );

    adapter = BaseHierarchyAdapter.fromTree(root);
    root.buildAddresses();
  });

  SignalOccurrence? resolve(String dotPath) {
    final addr = OccurrenceAddress.tryFromPathname(dotPath, root);
    if (addr == null) {
      return null;
    }
    return adapter.signalByAddress(addr);
  }

  group('findSignalById resolves ROHD dot-separated signal IDs', () {
    test('resolves top-level clk', () {
      final sig = resolve('abcd.clk');
      expect(sig, isNotNull);
      expect(sig!.path(), 'abcd/clk');
    });

    test('resolves top-level resetn', () {
      final sig = resolve('abcd.resetn');
      expect(sig, isNotNull);
      expect(sig!.path(), 'abcd/resetn');
    });

    test('resolves top-level arvalid_s', () {
      final sig = resolve('abcd.arvalid_s');
      expect(sig, isNotNull);
      expect(sig!.path(), 'abcd/arvalid_s');
    });

    test('resolves nested sub.data', () {
      final sig = resolve('abcd.sub.data');
      expect(sig, isNotNull);
      expect(sig!.path(), 'abcd/sub/data');
    });
  });
}
