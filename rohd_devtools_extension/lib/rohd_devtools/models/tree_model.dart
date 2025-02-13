// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.dart
// Model of the module tree hierarchy.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';

class TreeModel {
  final String name;
  final List<SignalModel> inputs;
  final List<SignalModel> outputs;
  final List<TreeModel> subModules;

  TreeModel({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.subModules,
  });

  factory TreeModel.fromJson(Map<String, dynamic> json) {
    List<SignalModel> inputSignalsList = [];
    List<SignalModel> outputSignalsList = [];

    for (var inputSignal in json['inputs'].entries) {
      SignalModel signal = SignalModel.fromMap({
        'name': inputSignal.key,
        'direction': 'Input',
        'value': inputSignal.value['value'],
        'width': inputSignal.value['width'],
      });
      inputSignalsList.add(signal);
    }

    for (var outputSignal in json['outputs'].entries) {
      SignalModel signal = SignalModel.fromMap({
        'name': outputSignal.key,
        'direction': 'Input',
        'value': outputSignal.value['value'],
        'width': outputSignal.value['width'],
      });

      outputSignalsList.add(signal);
    }

    return TreeModel(
      name: json['name'],
      inputs: inputSignalsList,
      outputs: outputSignalsList,
      subModules: (json["subModules"] as List)
          .map((subModule) => TreeModel.fromJson(subModule))
          .toList(),
    );
  }
}
