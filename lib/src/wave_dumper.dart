// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_dumper.dart
// Deprecated waveform dumper; use Module.dumpWaves instead.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Records VCD waveforms through [Module.dumpWaves] for legacy callers.
///
/// Use [Module.dumpWaves] for simple VCD output or [WaveformService] for
/// filtering, timescales, and recording windows.
@Deprecated('Use Module.dumpWaves() for simple VCD output, or '
    'WaveformService for advanced waveform configuration.')
class WaveDumper {
  final WaveformService _service;

  /// The [Module] being dumped.
  Module get module => _service.module;

  /// The output filepath of the generated waveforms.
  String get outputPath => _service.outputPath;

  /// Records all signal changes in the built [module] at [outputPath].
  @Deprecated('Use Module.dumpWaves() for simple VCD output, or '
      'WaveformService for advanced waveform configuration.')
  WaveDumper(Module module, {String outputPath = 'waves.vcd'})
      : _service = module.dumpWaves(outputPath: outputPath);
}
