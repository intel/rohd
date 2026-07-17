// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_dumper.dart
// Deprecated waveform dumper; use WaveformService instead.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>
// 2026 February - Added FST format support
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Waveform output format.
enum WaveFormat {
  /// VCD (Value Change Dump) text format.
  vcd,

  /// FST (Fast Signal Trace) binary format.
  fst,
}

/// Deprecated: use [WaveformService] instead.
///
/// [WaveDumper] is a compatibility wrapper around [WaveformService].
@Deprecated('Use WaveformService instead')
class WaveDumper {
  /// The underlying [WaveformService].
  final WaveformService _service;

  /// The [Module] being dumped.
  Module get module => _service.module;

  /// The output filepath of the generated waveforms.
  String get outputPath => _service.outputPath;

  /// The waveform output format.
  WaveFormat get format =>
      _service.format == WaveOutputFormat.fst ? WaveFormat.fst : WaveFormat.vcd;

  /// The FST writer configuration (only used when [format] is
  /// [WaveFormat.fst]).
  final FstWriterConfig? fstConfig;

  /// Attaches a [WaveDumper] to record all signal changes in a simulation of
  /// [module] in a waveform file at [outputPath].
  ///
  /// [module] must be built prior to construction.
  @Deprecated('Use WaveformService instead')
  WaveDumper(
    Module module, {
    String outputPath = 'waves.vcd',
    WaveFormat format = WaveFormat.vcd,
    this.fstConfig,
  }) : _service = WaveformService(
          module,
          outputPath: outputPath,
          format: format == WaveFormat.fst
              ? WaveOutputFormat.fst
              : WaveOutputFormat.vcd,
          fstConfig: fstConfig,
        );
}

/// Deprecated: use [WaveformService] instead.
@Deprecated('Use WaveformService instead')
typedef Dumper = WaveDumper;
