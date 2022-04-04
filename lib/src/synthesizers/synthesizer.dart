/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synthesizer.dart
/// Generic definition for something that synthesizes output files
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// An object capable of converting a module into some new output format
abstract class Synthesizer {
  /// Determines whether [module] needs a separate definition or can just be described in-line.
  bool generatesDefinition(Module module);

  /// Synthesizes [module] into a [SynthesisResult], given the mapping in [moduleToInstanceTypeMap].
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap);
}

/// An object representing the output of a Synthesizer
abstract class SynthesisResult {
  /// The top level [Module] associated with this result.
  final Module module;

  /// A [Map] from [Module] instances to synthesis instance type names.
  final Map<Module, String> moduleToInstanceTypeMap;

  SynthesisResult(this.module, this.moduleToInstanceTypeMap);

  /// Whether two implementations are identical or not
  ///
  /// Note: this doesn't include things like the top-level uniquified module
  /// name, just contents
  bool matchesImplementation(SynthesisResult other);

  /// Like the hashCode for [matchesImplementation] as an equality check.
  ///
  /// This is directly used as the [hashCode] of this object.
  int get matchHashCode;

  @override
  bool operator ==(Object other) =>
      other is SynthesisResult && matchesImplementation(other);

  @override
  int get hashCode => matchHashCode;

  /// Generates what could go into a file
  String toFileContents();
}
