// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_model.dart
// Model of the module tree hierarchy.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

class TreeModel {
  final String name;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> outputs;
  final List<TreeModel> subModules;

  TreeModel({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.subModules,
  });

  factory TreeModel.fromJson(Map<String, dynamic> json) {
    return TreeModel(
      name: json['name'],
      inputs: Map<String, List<String>>.from(json['inputs']),
      outputs: Map<String, List<String>>.from(json['outputs']),
      subModules: (json["subModules"] as List)
          .map((subModule) => TreeModel.fromJson(subModule))
          .toList(),
    );
  }
}
