/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synthesizer.dart
/// Generic definition for something that synthesizes output files
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// An object capable of converting a module into some new output format
abstract class Synthesizer {
  /// Determines whether [module] needs a separate definition or can just be
  /// described in-line.
  bool generatesDefinition(Module module);

  /// Synthesizes [module] into a [SynthesisResult], given the mapping in
  /// [moduleToInstanceTypeMap].
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap);
}
