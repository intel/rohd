// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Runnable hierarchy construction and search example.
//
// 2026 September 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

void main() {
  final root = HierarchyOccurrence(
    name: 'top',
    signals: [
      SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
      SignalOccurrence(name: 'count', width: 8),
    ],
    children: [
      HierarchyOccurrence(
        name: 'counter',
        definition: 'Counter',
        signals: [SignalOccurrence(name: 'enable', width: 1)],
      ),
    ],
  );
  final hierarchy = BaseHierarchyAdapter.fromTree(root);
  final clockSignals = hierarchy.searchSignals('clk');

  if (clockSignals.length != 1 ||
      clockSignals.single.path.join('/') != 'top/clk') {
    throw StateError('Expected to find the top-level clock signal.');
  }
}
