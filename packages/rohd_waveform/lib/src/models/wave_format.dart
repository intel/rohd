// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_format.dart
// Waveform file format enumeration.
//
// 2026 January 03
// Author: YDesmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

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
  unknown;

  /// Returns the file extension for this format.
  String get extension {
    switch (this) {
      case WaveFormat.vcd:
        return '.vcd';
      case WaveFormat.fst:
        return '.fst';
      case WaveFormat.ghw:
        return '.ghw';
      case WaveFormat.unknown:
        return '';
    }
  }

  /// Parses a format from a file path or extension.
  static WaveFormat fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vcd')) {
      return WaveFormat.vcd;
    }
    if (lower.endsWith('.fst')) {
      return WaveFormat.fst;
    }
    if (lower.endsWith('.ghw')) {
      return WaveFormat.ghw;
    }
    return WaveFormat.unknown;
  }

  /// Parses a format from a string name.
  static WaveFormat fromString(String name) {
    switch (name.toLowerCase()) {
      case 'vcd':
        return WaveFormat.vcd;
      case 'fst':
        return WaveFormat.fst;
      case 'ghw':
        return WaveFormat.ghw;
      default:
        return WaveFormat.unknown;
    }
  }

  /// Whether this format supports writing.
  bool get supportsWriting {
    switch (this) {
      case WaveFormat.vcd:
      case WaveFormat.fst:
        return true;
      case WaveFormat.ghw:
      case WaveFormat.unknown:
        return false;
    }
  }

  /// Whether this format supports reading.
  bool get supportsReading {
    switch (this) {
      case WaveFormat.vcd:
      case WaveFormat.fst:
      case WaveFormat.ghw:
        return true;
      case WaveFormat.unknown:
        return false;
    }
  }
}
