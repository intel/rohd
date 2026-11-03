// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_module_stop_policy.dart
// Shared module hierarchy stopping policy for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Determines whether a synthesizer should stop hierarchy traversal at a
/// [Module] and treat it as a leaf in its parent.
typedef SynthModuleLeafPredicate = bool Function(Module module);

/// Determines whether a [Module] would normally receive its own synthesized
/// definition before leaf predicates are applied.
typedef SynthModuleDefinitionPredicate = bool Function(Module module);

/// Shared hierarchy stopping policy for synthesis backends.
///
/// A synthesizer configures this with backend-specific leaf predicates and a
/// default definition rule, then queries [isLeaf] or [generatesDefinition]
/// while walking a module hierarchy.
class SynthModuleStopPolicy {
  final List<SynthModuleLeafPredicate> _leafPredicates;
  final SynthModuleDefinitionPredicate _generatesDefinitionByDefault;

  /// Creates a module stopping policy.
  SynthModuleStopPolicy({
    SynthModuleDefinitionPredicate? generatesDefinitionByDefault,
    Iterable<SynthModuleLeafPredicate> leafPredicates = const [],
  })  : _generatesDefinitionByDefault =
            generatesDefinitionByDefault ?? ((_) => true),
        _leafPredicates = List.unmodifiable(leafPredicates);

  /// Creates the default SystemVerilog stopping policy.
  factory SynthModuleStopPolicy.systemVerilog() => SynthModuleStopPolicy(
        leafPredicates: [
          (module) =>
              module is SystemVerilog &&
              module.generatedDefinitionType == DefinitionGenerationType.none,
        ],
      );

  /// Creates the default netlist stopping policy.
  factory SynthModuleStopPolicy.netlist({
    SynthModuleLeafPredicate leafModulePredicate = _isNetlistPrimitive,
  }) =>
      SynthModuleStopPolicy(
        generatesDefinitionByDefault: (module) => module.subModules.isNotEmpty,
        leafPredicates: [leafModulePredicate],
      );

  /// Returns `true` when [module] should be treated as a leaf cell in its
  /// parent instead of receiving its own generated definition.
  bool isLeaf(Module module) =>
      !_generatesDefinitionByDefault(module) ||
      _leafPredicates.any((predicate) => predicate(module));

  /// Returns `true` when [module] should receive its own generated definition.
  bool generatesDefinition(Module module) => !isLeaf(module);
}

bool _isNetlistPrimitive(Module module) =>
    module is Mux || module is FlipFlop || module is Passthrough;
