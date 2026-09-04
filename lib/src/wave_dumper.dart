// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_dumper.dart
// Deprecated waveform dumper; use Module.dumpWaves instead.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Deprecated: use [Module.dumpWaves] instead.
///
/// [WaveDumper] is a simple wrapper around [WaveformService] for backward
/// compatibility. It provides the legacy API for recording all signal changes
/// in a simulation to a VCD file.
///
/// **Migration guide:**
///
/// Replace:
/// ```dart
/// var dumper = WaveDumper(module, outputPath: 'output.vcd');
/// ```
///
/// With:
/// ```dart
/// var service = module.dumpWaves(outputPath: 'output.vcd');
/// ```
///
/// For more control over filtering, timescale, and recording windows, create a
/// [WaveformService] directly:
/// ```dart
/// final service = WaveformService(
///   module,
///   outputDirectory: 'build',
///   outputBaseName: 'debug',
///   writeToFile: true,
///   timescale: '1ns',
///   startTime: 100,
///   signalFilter: (signal) => signal.name.startsWith('debug_'),
/// );
/// ```
@Deprecated('Use Module.dumpWaves() for simple VCD output, or '
    'WaveformService for advanced waveform configuration.')
class WaveDumper {
  /// The underlying [WaveformService].
  final WaveformService _service;

  /// The [Module] being dumped.
  Module get module => _service.module;

  /// The output filepath of the generated waveforms.
  String get outputPath => _service.outputPath;

  /// Attaches a [WaveDumper] to record all signal changes in a simulation of
  /// [module] in a VCD file at [outputPath].
  ///
  /// [module] must be built prior to construction.
  ///
  /// **Deprecated:** Use [Module.dumpWaves] for simple VCD output, or
  /// [WaveformService] for signal filtering, custom timescale, recording
  /// windows, and extensibility hooks for streaming applications.
  @Deprecated('Use Module.dumpWaves() for simple VCD output, or '
      'WaveformService for advanced waveform configuration.')
  WaveDumper(Module module, {String outputPath = 'waves.vcd'})
      : _service = module.dumpWaves(outputPath: outputPath);
}

/// Deprecated: use [Module.dumpWaves] instead.
@Deprecated('Use Module.dumpWaves() for simple VCD output, or '
    'WaveformService for advanced waveform configuration.')
typedef Dumper = WaveDumper;
