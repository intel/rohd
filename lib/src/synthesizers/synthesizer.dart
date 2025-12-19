// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synthesizer.dart
// Generic definition for something that synthesizes output files
//
// 2021 August 26
// Author: Max Korbel <max.korbel@intel.com>
//

import 'package:rohd/rohd.dart';

/// An object capable of converting a module into some new output format
abstract class Synthesizer {
  /// Called by [SynthBuilder] before synthesis begins, with the top-level
  /// module(s) being synthesized.
  ///
  /// Override this method to perform any initialization that requires
  /// knowledge of the top module, such as resolving port names to [Logic]
  /// objects, or computing global signal sets.
  ///
  /// The default implementation does nothing.
  void prepare(List<Module> tops) {}

  /// Determines whether [module] needs a separate definition or can just be
  /// described in-line.
  bool generatesDefinition(Module module);

  /// Synthesizes [module] into a [SynthesisResult], given the mapping provided
  /// by [getInstanceTypeOfModule].
  ///
  /// Optionally a [lookupExistingResult] callback may be supplied which
  /// allows the synthesizer to query already-generated `SynthesisResult`s
  /// for child modules (useful when building parent output that needs
  /// information from children).
  SynthesisResult synthesize(
      Module module, String Function(Module module) getInstanceTypeOfModule,
      {SynthesisResult? Function(Module module)? lookupExistingResult,
      Map<Module, SynthesisResult>? existingResults});
}
