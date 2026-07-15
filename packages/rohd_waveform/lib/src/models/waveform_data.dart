// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_data.dart
// An entity that represents waveform data for a signal.
//
// 2024 December 30
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_waveform/src/models/data.dart';

/// A class that represents waveform data for a specific signal.
///
/// This class is used to transfer waveform data separately from the
/// signal structure, enabling incremental data loading and updates.
class WaveformData {
  /// The unique identifier of the signal this waveform data belongs to.
  final String signalId;

  /// The list of data points in the waveform.
  final List<Data> data;

  /// Whether this waveform was computed/synthesized (e.g. gate evaluation)
  /// rather than directly fetched from the VM service.
  final bool isComputed;

  /// Creates a new instance of [WaveformData].
  ///
  /// Requires [signalId] and [data] as parameters.
  WaveformData({
    required this.signalId,
    required this.data,
    this.isComputed = false,
  });

  /// Converts the [WaveformData] instance into a JSON Map.
  Map<String, dynamic> toJson() => {
        'signalId': signalId,
        'data': data.map((e) => e.toJson()).toList(),
      };

  /// Creates a new instance of [WaveformData] from a JSON Map.
  factory WaveformData.fromJson(Map<String, dynamic> json) => WaveformData(
        signalId: json['signalId'] as String,
        data: (json['data'] as List<dynamic>)
            .map((e) => Data.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Creates an empty waveform payload for [signalId].
  factory WaveformData.empty(String signalId) =>
      WaveformData(signalId: signalId, data: []);

  /// Returns the number of data points in the waveform.
  int get length => data.length;

  /// Returns true if the waveform has no data points.
  bool get isEmpty => data.isEmpty;

  /// Returns true if the waveform has data points.
  bool get isNotEmpty => data.isNotEmpty;

  /// Returns the time of the first data point, or null if empty.
  int? get startTime => data.isEmpty ? null : data.first.time;

  /// Returns the time of the last data point, or null if empty.
  int? get endTime => data.isEmpty ? null : data.last.time;

  @override
  String toString() => 'WaveformData($signalId, ${data.length} points)';
}
