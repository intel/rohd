// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.stub.dart
// The stub for tree model to be use in test.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

final class TreeModelStub {
  // Private named constructor
  const TreeModelStub._();

  static final simpleTreeModel = TreeModel(name: 'counter', inputs: [
    SignalModel.fromMap({
      'name': 'en',
      'direction': 'Input',
      'value': '1\'h0',
      'width': 1,
    }),
    SignalModel.fromMap({
      'name': 'reset',
      'direction': 'Input',
      'value': '1\'h1',
      'width': 1,
    }),
    SignalModel.fromMap({
      'name': 'clk',
      'direction': 'Input',
      'value': '1\'h0',
      'width': 1,
    }),
  ], outputs: [
    SignalModel.fromMap({
      'name': 'val',
      'direction': 'Input',
      'value': '1\'h0',
      'width': 1,
    }),
  ], subModules: [
    TreeModel(name: 'topmod', inputs: [
      SignalModel.fromMap({
        'name': 'in_a',
        'direction': 'Input',
        'value': '1\'h0',
        'width': 1,
      }),
      SignalModel.fromMap({
        'name': 'in_b',
        'direction': 'Input',
        'value': '1\'h1',
        'width': 1,
      }),
    ], outputs: [
      SignalModel.fromMap({
        'name': 'out_a',
        'direction': 'Input',
        'value': '1\'h1',
        'width': 1,
      }),
      SignalModel.fromMap({
        'name': 'out_b',
        'direction': 'Input',
        'value': '1\'h1',
        'width': 1,
      }),
    ], subModules: [])
  ]);

  static final selectedModule = TreeModel(name: 'topmod', inputs: [
    SignalModel.fromMap({
      'name': 'in_a',
      'direction': 'Input',
      'value': '1\'h0',
      'width': 1,
    }),
    SignalModel.fromMap({
      'name': 'in_b',
      'direction': 'Input',
      'value': '1\'h1',
      'width': 1,
    }),
  ], outputs: [
    SignalModel.fromMap({
      'name': 'out_a',
      'direction': 'Input',
      'value': '1\'h1',
      'width': 1,
    }),
    SignalModel.fromMap({
      'name': 'out_b',
      'direction': 'Input',
      'value': '1\'h1',
      'width': 1,
    }),
  ], subModules: []);
}
