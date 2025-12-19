// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_synthesizer.dart
// Synthesizer for schematic generation.
//
// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

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

  /// Top-level modules provided in [prepare]. Stored so `synthesize` can
  /// determine whether a module is a top-level module.
  Set<Module> _topModules = {};

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
    // Record top modules for later use in `synthesize`.
    _topModules = Set<Module>.from(tops);

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

  // ModuleMap-based helpers removed — Schematic synthesis prefers
  // child SchematicSynthesisResult objects and builder-local computations.

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
      Module module, String Function(Module module) getInstanceTypeOfModule,
      {SynthesisResult? Function(Module module)? lookupExistingResult,
      Map<Module, SynthesisResult>? existingResults}) {
    final builder = SchematicSynthesisResultBuilder(
      module: module,
      getInstanceTypeOfModule: getInstanceTypeOfModule,
      resolvedGlobalLogics: _resolvedGlobalLogics,
      filterConstInputsToCombinational: filterConstInputsToCombinational,
      lookupExistingResult: lookupExistingResult,
      existingResults: existingResults,
    );

    // If this module was one of the tops provided in `prepare`, tell the
    // builder so it can set the `top` attribute locally.
    final isTop = _topModules.contains(module);
    final result = builder.build(isTop: isTop);

    // Per-level structural validation
    _validateResult(result);

    // ID connectivity checks
    final idErrs = _validateIdConnectivity(result);
    if (idErrs.isNotEmpty) {
      final buf = StringBuffer()
        ..writeln('Schematic ID connectivity errors for ')
        ..writeln('  module: ${module.name}')
        ..writeln('Errors:');
      for (final e in idErrs) {
        buf.writeln('  - $e');
      }
      throw StateError(buf.toString());
    }

    // If this is a top-level module, validate the entire hierarchy for
    // cycles/duplicate instances.
    if (isTop) {
      _validateHierarchyForTop(module);
    }

    return result;
  }

  /// Run basic result validation using a ModuleMap constructed from the
  /// result's module. This delegates to the existing ModuleMap.validate()
  /// implementation.
  void _validateResult(SchematicSynthesisResult result) {
    final module = result.module;
    final globalLogics = result.globalLogics;

    // Recompute portLogics and internalLogics as ModuleMap did.
    final portLogics = <Logic, List<int>>{};
    final internalLogics = <Logic, List<int>>{};

    // Compute reachable from globals
    final reachableFromGlobals = <Logic>{};
    if (globalLogics.isNotEmpty) {
      final visitQueue = <Logic>[...globalLogics];
      while (visitQueue.isNotEmpty) {
        final cur = visitQueue.removeLast();
        if (reachableFromGlobals.contains(cur)) {
          continue;
        }
        reachableFromGlobals.add(cur);
        for (final dst in cur.dstConnections) {
          if (!reachableFromGlobals.contains(dst)) {
            visitQueue.add(dst);
          }
        }
      }
    }

    var nextId = 0;
    final portCandidates = <Logic>[
      ...module.inputs.values,
      ...module.outputs.values,
      ...module.inOuts.values
    ];
    for (final logic in portCandidates) {
      if (reachableFromGlobals.contains(logic)) {
        continue;
      }
      final ids = List<int>.generate(logic.width, (_) => nextId++);
      portLogics[logic] = ids;
    }

    // internals: include signals that are not ports
    final internalSignals = [
      for (final s in module.signals)
        if (!portLogics.containsKey(s)) s
    ];
    for (final sig in internalSignals) {
      if (reachableFromGlobals.contains(sig)) {
        continue;
      }
      final ids = List<int>.generate(sig.width, (_) => nextId++);
      internalLogics[sig] = ids;
    }

    // Now perform the same validation logic as ModuleMap.validate()
    final logicToIds = <Logic, List<int>>{}
      ..addAll(portLogics)
      ..addAll(internalLogics);
    final allLogics = <Logic>[...portLogics.keys, ...internalLogics.keys];
    for (final l in allLogics) {
      if (!logicToIds.containsKey(l)) {
        throw StateError(
            'Logic $l missing ids in module ${module.uniqueInstanceName}');
      }
    }

    final bitIdToMembers = <int, List<Logic>>{};
    for (final e in logicToIds.entries) {
      for (final bitId in e.value) {
        bitIdToMembers.putIfAbsent(bitId, () => []).add(e.key);
      }
    }

    final signals = [...portLogics.keys, ...internalLogics.keys];
    final indexOf = {for (var i = 0; i < signals.length; i++) signals[i]: i};
    final unions = <List<int>>[
      for (var i = 0; i < signals.length; i++)
        for (final conn in [
          ...signals[i].srcConnections,
          ...signals[i].dstConnections
        ])
          if (indexOf[conn] != null) [i, indexOf[conn]!]
    ];

    final roots =
        SchematicSynthesisResult.computeComponents(signals.length, unions);

    for (final members in bitIdToMembers.values) {
      if (members.length <= 1) {
        continue;
      }
      final root0 = roots[indexOf[members.first]!];
      for (final other in members.skip(1)) {
        final rootN = roots[indexOf[other]!];
        if (root0 != rootN) {
          final buf = StringBuffer()
            ..writeln('Members ${members.first} and $other share '
                'bit-id but are not in same component in ')
            ..writeln(module.uniqueInstanceName)
            ..writeln('Member info:');
          for (final m in members) {
            buf.writeln('  - $m (ids=${logicToIds[m]}, '
                'root=${roots[indexOf[m]!]}');
          }
          throw StateError(buf.toString());
        }
      }
    }

    // Recurse into submodules
    for (final sub in module.subModules) {
      // Build a result-like check by using existing SchematicSynthesisResult if
      // available in synthesis flow; otherwise we still validate the Module
      // structure by recursing on the Module object.
      // For now, validate using Module semantics recursively.
      // (This mirrors ModuleMap's recursive validate())
      // Construct a minimal temporary SchematicSynthesisResult with empty
      // mappings and the resolved child globals.
      final childGlobals = <Logic>{};
      if (reachableFromGlobals.isNotEmpty) {
        for (final input in sub.inputs.values) {
          for (final src in input.srcConnections) {
            if (reachableFromGlobals.contains(src)) {
              childGlobals.add(input);
              break;
            }
          }
        }
      }
      // Recursively validate child module structure
      _validateResult(SchematicSynthesisResult(
        sub,
        (m) => m.definitionName,
        ports: const {},
        portLogics: const {},
        globalLogics: childGlobals,
        cells: const {},
        netnames: const {},
      ));
    }
  }

  /// Compute port and internal schematic id maps for [module], excluding
  /// signals reachable from [globalLogics]. Returns a map with keys
  /// 'ports' and 'internals'.
  Map<String, Map<Logic, List<int>>> _computePortAndInternalIds(
      Module module, Set<Logic> globalLogics) {
    final portLogics = <Logic, List<int>>{};
    final internalLogics = <Logic, List<int>>{};

    final reachableFromGlobals = <Logic>{};
    if (globalLogics.isNotEmpty) {
      final visitQueue = <Logic>[...globalLogics];
      while (visitQueue.isNotEmpty) {
        final cur = visitQueue.removeLast();
        if (reachableFromGlobals.contains(cur)) {
          continue;
        }
        reachableFromGlobals.add(cur);
        for (final dst in cur.dstConnections) {
          if (!reachableFromGlobals.contains(dst)) {
            visitQueue.add(dst);
          }
        }
      }
    }

    var nextId = 0;
    final portCandidates = <Logic>[
      ...module.inputs.values,
      ...module.outputs.values,
      ...module.inOuts.values
    ];
    for (final logic in portCandidates) {
      if (reachableFromGlobals.contains(logic)) {
        continue;
      }
      final ids = List<int>.generate(logic.width, (_) => nextId++);
      portLogics[logic] = ids;
    }

    final internalSignals = [
      for (final s in module.signals)
        if (!portLogics.containsKey(s)) s
    ];
    for (final sig in internalSignals) {
      if (reachableFromGlobals.contains(sig)) {
        continue;
      }
      final ids = List<int>.generate(sig.width, (_) => nextId++);
      internalLogics[sig] = ids;
    }

    return {
      'ports': portLogics,
      'internals': internalLogics,
    };
  }

  /// Validate id connectivity for a single module result by delegating to
  /// ModuleMap.validateIdConnectivity(). Returns a list of error messages.
  List<String> _validateIdConnectivity(SchematicSynthesisResult result) {
    final errors = <String>[];
    final module = result.module;

    final maps = _computePortAndInternalIds(module, result.globalLogics);
    final portLogics = maps['ports']!;
    final internalLogics = maps['internals']!;

    final allIds = <int, Logic>{};

    void checkIds(Logic logic, List<int> ids, String context) {
      for (final id in ids) {
        if (id < 0) {
          errors.add('$context: Logic "${logic.name}" has negative id $id');
        }
        final existing = allIds[id];
        if (existing != null && existing != logic) {
          final connected = logic.srcConnections.contains(existing) ||
              logic.dstConnections.contains(existing) ||
              existing.srcConnections.contains(logic) ||
              existing.dstConnections.contains(logic);
          if (!connected) {
            errors.add(
              '$context: ID $id assigned to both "${logic.name}" and '
              '"${existing.name}" but they are not connected',
            );
          }
        }
        allIds[id] = logic;
      }
    }

    for (final entry in portLogics.entries) {
      checkIds(entry.key, entry.value, module.uniqueInstanceName);
    }
    for (final entry in internalLogics.entries) {
      checkIds(
          entry.key, entry.value, '${module.uniqueInstanceName} (internal)');
    }

    // Recurse into child results if present
    for (final child in result.childResults) {
      if (child != null) {
        errors.addAll(_validateIdConnectivity(child));
      }
    }

    // Primitive input driver checks
    for (final sub in module.subModules) {
      var prim = Primitives.instance.lookupByDefinitionName(sub.definitionName);
      if (prim == null && sub.subModules.isEmpty) {
        prim = Primitives.instance.lookupForModule(sub);
      }
      if (prim == null) {
        continue;
      }
      for (final inLogic in sub.inputs.values) {
        if (inLogic.srcConnections.isEmpty) {
          errors.add(
            '${module.uniqueInstanceName}: Primitive '
            '${sub.uniqueInstanceName} input "${inLogic.name}" has no driver',
          );
        }
      }
    }

    return errors;
  }

  /// Validate the hierarchical placement of modules starting at [top]. This
  /// will raise if cycles or duplicate-hierarchy placements are detected.
  void _validateHierarchyForTop(Module top) {
    // Validate hierarchy for cycles and duplicate placements.
    void visit(Module m, List<Module> hierarchy,
        Map<Module, List<List<int>>> visitedPaths) {
      final newHierarchy = [...hierarchy, m];

      // Detect cycles by module identity
      if (hierarchy.any((mm) => mm == m)) {
        final loop = newHierarchy.map((x) => x.uniqueInstanceName).join('.');
        throw StateError(
            'Module ${m.uniqueInstanceName} is a submodule of itself: $loop');
      }

      if (visitedPaths.containsKey(m)) {
        final otherPaths =
            visitedPaths[m]!.map((p) => p.map((i) => i).join('.')).join(',');
        final thisStr = hierarchy.map((mm) => mm.uniqueInstanceName).join('.');
        throw StateError(
            'Module ${m.uniqueInstanceName} exists at more than one '
            'hierarchy: $otherPaths and $thisStr');
      }

      visitedPaths[m] = [newHierarchy.map((x) => x.hashCode).toList()];

      for (final sub in m.subModules) {
        visit(sub, newHierarchy, visitedPaths);
      }
    }

    visit(top, [], <Module, List<List<int>>>{});
  }

  /// Collects a combined modules map from a collection of [SynthesisResult]s
  /// suitable for JSON emission (matches previous test helpers).
  ///
  /// Each entry is keyed by the result's `instanceTypeName` and contains the
  /// `attributes`, `ports`, `cells`, and `netnames` maps. If a [topModule]
  /// is supplied, the corresponding module's attributes will include
  /// `'top': 1`.
  Map<String, Map<String, Object?>> collectModuleEntries(
      Iterable<SynthesisResult> results,
      {Module? topModule}) {
    final allModules = <String, Map<String, Object?>>{};
    for (final result in results) {
      if (result is SchematicSynthesisResult) {
        final typeName = result.instanceTypeName;
        final attrs = Map<String, Object?>.from(result.attributes);
        if (topModule != null && result.module == topModule) {
          attrs['top'] = 1;
        }
        allModules[typeName] = {
          'attributes': attrs,
          'ports': result.ports,
          'cells': result.cells,
          'netnames': result.netnames,
        };
      }
    }
    return allModules;
  }

  /// Generate the combined ROHD schematic JSON from a SynthBuilder's
  /// `synthesisResults`. Returns the JSON string.
  Future<String> generateCombinedJson(SynthBuilder synth, Module top) async {
    final modules =
        collectModuleEntries(synth.synthesisResults, topModule: top);
    final combined = {
      'creator': 'SchematicSynthesizer via SynthBuilder (rohd)',
      'modules': modules,
    };
    return const JsonEncoder.withIndent('  ').convert(combined);
  }

  /// Convenience API: synthesize [top] into a combined ROHD JSON string.
  /// This builds a `SynthBuilder` internally with `this` synthesizer and
  /// returns the full JSON contents (including the `creator` field).
  Future<String> synthesizeToJson(Module top) async {
    final sb = SynthBuilder(top, this);
    return generateCombinedJson(sb, top);
  }
}
