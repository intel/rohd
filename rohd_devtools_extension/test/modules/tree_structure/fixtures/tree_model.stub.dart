// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.stub.dart
// The stub for tree model to be use in test.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

final class TreeModelStub {
  // Private named constructor
  const TreeModelStub._();

  static final simpleTreeModel = HierarchyOccurrence(
    name: 'counter',
    signals: [
      // Inputs
      SignalOccurrence(name: 'en', width: 1, direction: 'input'),
      SignalOccurrence(name: 'reset', width: 1, direction: 'input'),
      SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
      // Outputs
      SignalOccurrence(name: 'val', width: 1, direction: 'output'),
    ],
    children: [
      HierarchyOccurrence(
        name: 'topmod',
        signals: [
          // Inputs
          SignalOccurrence(name: 'in_a', width: 1, direction: 'input'),
          SignalOccurrence(name: 'in_b', width: 1, direction: 'input'),
          // Outputs
          SignalOccurrence(name: 'out_a', width: 1, direction: 'output'),
          SignalOccurrence(name: 'out_b', width: 1, direction: 'output'),
        ],
        children: [],
      ),
    ],
  );

  static final selectedModule = HierarchyOccurrence(
    name: 'topmod',
    signals: [
      // Inputs
      SignalOccurrence(name: 'in_a', width: 1, direction: 'input'),
      SignalOccurrence(name: 'in_b', width: 1, direction: 'input'),
      // Outputs
      SignalOccurrence(name: 'out_a', width: 1, direction: 'output'),
      SignalOccurrence(name: 'out_b', width: 1, direction: 'output'),
    ],
    children: [],
  );
}
