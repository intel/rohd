// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_format.dart
// Waveform file format enumeration.
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Supported waveform file formats.
enum WaveFormat {
  /// Value Change Dump format (IEEE 1364).
  ///
  /// VCD is the most widely supported format, but can produce very large
  /// files for complex simulations.
  vcd,

  /// Fast Signal Trace format (GTKWave).
  ///
  /// FST is a compressed binary format that is much more efficient than VCD.
  /// It supports random access and is the recommended format for large
  /// simulations.
  fst,

  /// GHDL Waveform format.
  ///
  /// GHW is the native format for GHDL simulations. Reading is supported,
  /// but writing is not.
  ghw,

  /// Unknown or unsupported format.
  unknown(extension: '');

  const WaveFormat({String? extension}) : _extension = extension;

  final String? _extension;

  /// Returns the file extension for this format.
  String get extension => _extension ?? '.$name';

  /// Parses a format from a file path or extension.
  static WaveFormat fromPath(String path) {
    final lower = path.toLowerCase();
    for (final format in values) {
      if (format.extension.isNotEmpty && lower.endsWith(format.extension)) {
        return format;
      }
    }
    return WaveFormat.unknown;
  }

  /// Parses a format from a string name.
  static WaveFormat fromString(String name) {
    final lower = name.toLowerCase();
    for (final format in values) {
      if (format.name == lower) {
        return format;
      }
    }
    return WaveFormat.unknown;
  }
}
