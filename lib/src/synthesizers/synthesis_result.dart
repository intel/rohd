// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synthesis_result.dart
// Generic definition for the result of synthesizing a Module.
//
// 2021 August 26
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// An object representing the output of a Synthesizer for one [module].
@immutable
abstract class SynthesisResult {
  /// The top level [Module] associated with this result.
  final Module module;

  /// A [Map] from [Module] instances to synthesis instance type names.
  @protected
  final String Function(Module module) getInstanceTypeOfModule;

  /// The name of the definition type for this module instance.
  String get instanceTypeName => getInstanceTypeOfModule(module);

  /// Represents a constant computed synthesis result for [module] given
  /// the provided type mapping in [getInstanceTypeOfModule].
  const SynthesisResult(this.module, this.getInstanceTypeOfModule);

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
      other is SynthesisResult &&
      matchesImplementation(other) &&
      // if they are both reserved defs but different def names, not equal
      !((module.reserveDefinitionName && other.module.reserveDefinitionName) &&
          module.definitionName != other.module.definitionName);

  @override
  int get hashCode => matchHashCode;

  /// Generates what could go into a file.
  @Deprecated('Use `toSynthFileContents()` instead.')
  String toFileContents();

  /// Generates contents for a number of files.
  List<SynthFileContents> toSynthFileContents();

  /// If provided, a [List] of additional [Module]s that should be included in
  /// the generated results.
  ///
  /// This is intended for cases where a supporting additional module
  /// declaration is required for functionality of the generated output.
  List<Module>? get supportingModules => null;
}
