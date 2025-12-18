// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_synthesizer.dart
// Synthesizer for schematic generation.
//
// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic.dart';

/// A [Synthesizer] that generates schematic output (Yosys JSON format).
///
/// Unlike the standalone `SchematicDumper`, this synthesizer integrates with
/// [SynthBuilder] to handle module hierarchy recursion automatically. Each
/// [synthesize] call produces a [SchematicSynthesisResult] for one module
/// level.
///
/// ## Options
///
/// - [filterConstInputsToCombinational]: When true, filters out constant-only
///   inputs to combinational primitives from the output.
///
/// - [globalPortNames]: A list of port names on the **top module** that should
///   be treated as "global" signals (e.g., clock, reset). These signals and any
///   signals reachable from them will be excluded from connectivity generation.
///   The names are resolved in [prepare] when SynthBuilder starts.
///
/// - [globalLogics]: Alternatively, you can directly provide a set of [Logic]
///   objects to treat as global. This takes precedence over [globalPortNames].
///
/// Example:
/// ```dart
/// final synth = SchematicSynthesizer(
///   filterConstInputsToCombinational: true,
///   globalPortNames: ['clk', 'reset'],
/// );
/// final builder = SynthBuilder(topModule, synth);
/// ```
class SchematicSynthesizer extends Synthesizer {
  /// Whether to filter const-only inputs to combinational primitives.
  final bool filterConstInputsToCombinational;

  /// Port names on the top module to treat as global signals.
  ///
  /// These are resolved to [Logic] objects in [prepare] when SynthBuilder
  /// starts synthesis. Signals reachable from these ports will be excluded
  /// from connectivity generation.
  final List<String> globalPortNames;

  /// Explicit set of [Logic] objects to treat as global.
  ///
  /// If provided, this takes precedence over [globalPortNames]. These signals
  /// and any signals reachable from them will be excluded from connectivity
  /// generation.
  final Set<Logic>? globalLogics;

  /// Resolved global logics, computed in [prepare].
  Set<Logic> _resolvedGlobalLogics = {};

  /// Creates a [SchematicSynthesizer].
  ///
  /// - [filterConstInputsToCombinational]: When true, filters out constant-only
  ///   inputs to combinational primitives.
  /// - [globalPortNames]: Port names on the top module to treat as global.
  /// - [globalLogics]: Explicit [Logic] objects to treat as global (takes
  ///   precedence over [globalPortNames]).
  SchematicSynthesizer({
    this.filterConstInputsToCombinational = false,
    this.globalPortNames = const [],
    this.globalLogics,
  });

  @override
  void prepare(List<Module> tops) {
    // Resolve global logics from the top module(s)
    _resolvedGlobalLogics = {};

    // If explicit globalLogics provided, use them
    if (globalLogics != null && globalLogics!.isNotEmpty) {
      _resolvedGlobalLogics = Set<Logic>.from(globalLogics!);
      return;
    }

    // Otherwise resolve from port names on the first top module
    if (globalPortNames.isEmpty || tops.isEmpty) {
      return;
    }

    final topModule = tops.first;
    for (final name in globalPortNames) {
      // Check inputs, outputs, and inOuts
      final port = topModule.inputs[name] ??
          topModule.outputs[name] ??
          topModule.inOuts[name];
      if (port != null) {
        _resolvedGlobalLogics.add(port);
      }
    }

    if (_resolvedGlobalLogics.isEmpty && globalPortNames.isNotEmpty) {
      throw StateError(
        'No top-level ports found matching globalPortNames $globalPortNames. '
        'Ensure the top module declares ports with these names.',
      );
    }
  }

  @override
  bool generatesDefinition(Module module) {
    // Check if module uses Schematic mixin and controls definition generation
    if (module is Schematic) {
      return module.schematicDefinitionType !=
          SchematicDefinitionGenerationType.none;
    }

    // Primitives don't generate separate definitions - they're inlined
    final prim = Primitives.instance.lookupForModule(module);
    return prim == null;
  }

  @override
  SynthesisResult synthesize(
      Module module, String Function(Module module) getInstanceTypeOfModule) {
    // Create a ModuleMap for this single module level (no recursive submodules)
    // The SynthBuilder handles the recursion.
    final map = ModuleMap(
      module,
      includeInternals: true,
      globalLogics:
          _resolvedGlobalLogics.isNotEmpty ? _resolvedGlobalLogics : null,
    );

    // Validate the ModuleMap hierarchy and connectivity similarly to
    // SchematicDumper to provide early, clear errors for cycles/invalid maps.
    try {
      map
        ..validateHierarchy(visited: <Module, List<ModuleMap>>{})
        ..validate();
      final idErrors = map.validateIdConnectivity();
      if (idErrors.isNotEmpty) {
        final buf = StringBuffer()..writeln('ID connectivity errors:');
        for (final e in idErrors) {
          buf.writeln('  - $e');
        }
        throw StateError(buf.toString());
      }
    } catch (e) {
      throw StateError(
          'ModuleMap validation failed before schematic synth: $e');
    }

    final builder = SchematicSynthesisResultBuilder(
      module: module,
      map: map,
      getInstanceTypeOfModule: getInstanceTypeOfModule,
      filterConstInputsToCombinational: filterConstInputsToCombinational,
    );

    return builder.build();
  }
}
