// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// metadata.dart
// An entity that describes the metadata of a module structure.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:equatable/equatable.dart';
import 'package:rohd_waveform/src/models/wave_format.dart';

/// A class that represents the metadata of a module structure.
///
/// It contains source, timescale, date, and time range information.
class MetaData extends Equatable {
  /// The source of the metadata.
  final String source;

  /// The timescale of the metadata (e.g., "1ns", "100ps").
  final String timescale;

  /// The timescale factor (e.g., 1, 10, 100).
  ///
  /// This is optional and populated when loading from waveform files.
  final int? timescaleFactor;

  /// The date of the metadata.
  final String date;

  /// The version string (if available).
  ///
  /// This is optional and populated when loading from waveform files.
  final String? version;

  /// The file format.
  ///
  /// This is optional and populated when loading from waveform files.
  final WaveFormat? format;

  /// The start time of the waveform in timescale units.
  final int startTime;

  /// The end time of the waveform in timescale units.
  final int endTime;

  /// Creates a new instance of [MetaData].
  ///
  /// Requires [source], [timescale], and [date] as parameters.
  /// [startTime] and [endTime] default to 0 if not provided.
  /// [timescaleFactor], [version], and [format] are optional.
  const MetaData({
    required this.source,
    required this.timescale,
    required this.date,
    this.startTime = 0,
    this.endTime = 0,
    this.timescaleFactor,
    this.version,
    this.format,
  });

  /// Converts the [MetaData] instance into a JSON Map.
  Map<String, dynamic> toJson() => {
        'source': source,
        'timescale': timescale,
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        if (timescaleFactor != null) 'timescaleFactor': timescaleFactor,
        if (version != null) 'version': version,
        if (format != null) 'format': format!.name,
      };

  /// Creates a new instance of [MetaData] from a JSON Map.
  factory MetaData.fromJson(Map<String, dynamic> json) => MetaData(
        source: json['source'] as String,
        timescale: json['timescale'] as String,
        date: json['date'] as String,
        startTime: (json['startTime'] ?? 0) as int,
        endTime: (json['endTime'] ?? 0) as int,
        timescaleFactor: json['timescaleFactor'] as int?,
        version: json['version'] as String?,
        format: json['format'] != null
            ? WaveFormat.fromString(json['format'] as String)
            : null,
      );

  /// Creates an empty metadata object.
  factory MetaData.empty() => const MetaData(
        source: '',
        timescale: '',
        date: '',
      );

  @override
  List<Object?> get props => [
        source,
        timescale,
        timescaleFactor,
        date,
        version,
        format,
        startTime,
        endTime,
      ];
}
