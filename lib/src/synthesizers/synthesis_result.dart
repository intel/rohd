/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synthesis_result.dart
/// Generic definition for the result of synthesizing a Module.
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// An object representing the output of a Synthesizer
@immutable
abstract class SynthesisResult {
  /// The top level [Module] associated with this result.
  final Module module;

  /// A [Map] from [Module] instances to synthesis instance type names.
  @protected
  final Map<Module, String> moduleToInstanceTypeMap;

  /// The name of the definition type for this module instance.
  String get instanceTypeName => moduleToInstanceTypeMap[module]!;

  /// Represents a constant computed synthesis result for [module] given
  /// the provided type mapping in [moduleToInstanceTypeMap].
  const SynthesisResult(this.module, this.moduleToInstanceTypeMap);

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
