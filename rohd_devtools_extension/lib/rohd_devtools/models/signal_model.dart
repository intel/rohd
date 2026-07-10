// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_model.dart
// Model of the signal shown in the details table.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

/// Model of a signal shown in the details table.
class SignalModel {
  /// Signal name.
  final String name;

  /// Signal direction label.
  final String direction;

  /// Signal value rendered as text.
  final String value;

  /// Signal bit width.
  final int width;

  /// Creates a signal model.
  SignalModel(
      {required this.name,
      required this.direction,
      required this.value,
      required this.width});

  /// Builds a signal model from a map representation.
  factory SignalModel.fromMap(Map<String, dynamic> map) => SignalModel(
      name: map['name'] as String,
      direction: map['direction'] as String,
      value: map['value'] as String,
      width: map['width'] as int);

  /// Converts the signal model to a JSON-compatible map.
  Map<String, dynamic> toMap() =>
      {'name': name, 'direction': direction, 'value': value, 'width': width};
}
