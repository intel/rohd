// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.dart
// Model of the module tree hierarchy.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';

/// Hierarchical model of a ROHD module tree.
class TreeModel {
  /// Module name.
  final String name;

  /// Input signals for the module.
  final List<SignalModel> inputs;

  /// Output signals for the module.
  final List<SignalModel> outputs;

  /// Child submodules contained by this module.
  final List<TreeModel> subModules;

  /// Creates a tree model for a module hierarchy node.
  TreeModel({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.subModules,
  });

  /// Builds a tree model from a JSON map.
  factory TreeModel.fromJson(Map<String, dynamic> json) {
    final inputSignalsList = <SignalModel>[];
    final outputSignalsList = <SignalModel>[];
    final inputsJson = json['inputs'] as Map<String, dynamic>;
    final outputsJson = json['outputs'] as Map<String, dynamic>;

    for (final inputSignal in inputsJson.entries) {
      final inputValue = inputSignal.value as Map<String, dynamic>;
      final signal = SignalModel.fromMap({
        'name': inputSignal.key,
        'direction': 'Input',
        'value': inputValue['value'],
        'width': inputValue['width'],
      });
      inputSignalsList.add(signal);
    }

    for (final outputSignal in outputsJson.entries) {
      final outputValue = outputSignal.value as Map<String, dynamic>;
      final signal = SignalModel.fromMap({
        'name': outputSignal.key,
        'direction': 'Output',
        'value': outputValue['value'],
        'width': outputValue['width'],
      });

      outputSignalsList.add(signal);
    }

    return TreeModel(
      name: json['name'] as String,
      inputs: inputSignalsList,
      outputs: outputSignalsList,
      subModules: (json['subModules'] as List)
          .map((subModule) =>
              TreeModel.fromJson(subModule as Map<String, dynamic>))
          .toList(),
    );
  }
}
