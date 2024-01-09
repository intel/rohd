// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.stub.dart
// The stub for tree model to be use in test.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';

final class TreeModelStub {
  // Private named constructor
  const TreeModelStub._();

  static final simpleTreeModel = TreeModel(name: 'counter', inputs: {
    'en': '1\'h0',
    'reset': '\'1h1',
    'clk': '1\'h1',
  }, outputs: {
    'val': '1h0',
  }, subModules: [
    TreeModel(name: 'topmod', inputs: {
      'in_a': '1\'h0',
      'in_b': '1\'h1',
    }, outputs: {
      'out_a': '1\'h1',
      'out_b': '1\'h1',
    }, subModules: [])
  ]);

  static final selectedModule = TreeModel(name: 'topmod', inputs: {
    'in_a': '1\'h0',
    'in_b': '1\'h1',
  }, outputs: {
    'out_a': '1\'h1',
    'out_b': '1\'h1',
  }, subModules: []);
}
