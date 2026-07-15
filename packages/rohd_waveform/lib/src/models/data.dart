// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// data.dart
// An entity that describes the data of a signal.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

/// A class that represents the data of a signal.
///
/// It contains a time and a value.
class Data {
  /// The time of the data.
  int time;

  /// The value of the data.
  String value;

  /// Creates a new instance of [Data].
  ///
  /// Requires [time] and [value] as parameters.
  Data({required this.time, required this.value});

  /// Converts the [Data] instance into a JSON Map.
  Map<String, dynamic> toJson() => {'time': time, 'value': value};

  /// Creates a new instance of [Data] from a JSON Map.
  factory Data.fromJson(Map<String, dynamic> json) =>
      Data(time: json['time'] as int, value: json['value'] as String);

  /// Creates an empty data point at time zero with value `0`.
  factory Data.empty() => Data(time: 0, value: '0');
}
