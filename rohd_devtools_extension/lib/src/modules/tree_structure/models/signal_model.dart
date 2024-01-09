// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_model.dart
// Model of the signal to be tabulate on the detail table.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

class SignalModel {
  final String name;
  final String direction;
  final String value;
  final int width;

  SignalModel({
    required this.name,
    required this.direction,
    required this.value,
    required this.width,
  });

  factory SignalModel.fromMap(Map<String, dynamic> map) {
    return SignalModel(
      name: map['name'] as String,
      direction: map['direction'] as String,
      value: map['value'] as String,
      width: map['width'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'direction': direction,
      'value': value,
      'width': width,
    };
  }
}
