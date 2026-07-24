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
/// A synthesizer configures this with backend-specific leaf module types,
/// predicates, and a default definition rule, then queries [isLeaf] or
/// [generatesDefinition] while walking a module hierarchy.
class SynthModuleStopPolicy {
  final Set<Type> _leafModuleTypes;
  final List<SynthModuleLeafPredicate> _leafPredicates;
  final SynthModuleDefinitionPredicate _generatesDefinitionByDefault;

  /// Creates a module stopping policy.
  SynthModuleStopPolicy({
    SynthModuleDefinitionPredicate? generatesDefinitionByDefault,
    Iterable<Type> leafModuleTypes = const [],
    Iterable<SynthModuleLeafPredicate> leafPredicates = const [],
  })  : _generatesDefinitionByDefault =
            generatesDefinitionByDefault ?? ((_) => true),
        _leafModuleTypes = Set.unmodifiable(leafModuleTypes),
        _leafPredicates = List.unmodifiable(leafPredicates);

  /// Creates the default SystemVerilog stopping policy.
  factory SynthModuleStopPolicy.systemVerilog() => SynthModuleStopPolicy(
        leafPredicates: [
          (module) {
            // ignore: deprecated_member_use_from_same_package
            if (module is CustomSystemVerilog) {
              return true;
            }

            return module is SystemVerilog &&
                module.generatedDefinitionType == DefinitionGenerationType.none;
          },
        ],
      );

  /// Creates the default netlist stopping policy.
  factory SynthModuleStopPolicy.netlist({
    Iterable<Type> leafModuleTypes = const [FlipFlop],
    Iterable<SynthModuleLeafPredicate> leafPredicates = const [],
  }) =>
      SynthModuleStopPolicy(
        generatesDefinitionByDefault: (module) => module.subModules.isNotEmpty,
        leafModuleTypes: leafModuleTypes,
        leafPredicates: leafPredicates,
      );

  /// Returns `true` when [module] should be treated as a leaf cell in its
  /// parent instead of receiving its own generated definition.
  bool isLeaf(Module module) =>
      !_generatesDefinitionByDefault(module) ||
      _leafModuleTypes.contains(module.runtimeType) ||
      _leafPredicates.any((predicate) => predicate(module));

  /// Returns `true` when [module] should receive its own generated definition.
  bool generatesDefinition(Module module) => !isLeaf(module);
}
