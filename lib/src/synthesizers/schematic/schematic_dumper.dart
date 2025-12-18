// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_dumper.dart
// Schematic dumping into ELK-JSON Yosys format.

// 2025 December 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';

import 'package:rohd/src/synthesizers/schematic/schematic.dart';

/// Helper: follow srcConnection chain to return canonical driver Logic.
Logic getCanonicalLogic(Logic logic) {
  var cur = logic;
  final visited = <int>{};
  while (cur.srcConnection != null && !visited.contains(cur.hashCode)) {
    visited.add(cur.hashCode);
    cur = cur.srcConnection!;
  }
  return cur;
}

/// Lightweight schematic dumper similar in intent to WaveDumper.
class SchematicDumper {
  /// The top-level module provided to the dumper.
  final Module topModule;

  /// The constructed module map for the top module.
  final ModuleMap topMap;

  /// Optional output path (mirrors WaveDumper's `outputPath` argument).
  final String? outputPath;

  /// Whether to filter out input ports driven only by constants.

  final bool filterConstInputsToCombinational;

  /// Construct a `SchematicDumper` directly from [module]. The
  /// [includeInternals] flag controls whether internal signals and submodules
  /// are mapped.
  SchematicDumper(Module module,
      {bool includeInternals = true,
      this.outputPath,
      this.filterConstInputsToCombinational = false,
      List<String>? globalPortNames})
      : topModule = module,
        topMap = (() {
          // Build an initial set of global Logics based on explicit top-level
          // port names.
          final gnames = globalPortNames ?? <String>[];
          final globals = <Logic>{};
          if (gnames.isNotEmpty) {
            globals
                .addAll(gnames.map((n) => module.ports[n]).whereType<Logic>());
            if (globals.isEmpty) {
              throw StateError(
                  'No top-level ports found matching globalPortNames $gnames. '
                  'Ensure the top module declares ports with these names or '
                  'pass appropriate Logic ports to the dumper.');
            }
          }

          return ModuleMap(module,
              includeInternals: includeInternals,
              globalLogics: globals.isEmpty ? null : globals);
        })() {
    if (outputPath != null) {
      // Synchronous export: require the module to already be built.
      if (!module.hasBuilt) {
        throw StateError('Top module must be built before constructor export');
      }
      final out = outputPath!;
      _exportYosysJson(out);
    }
  }

  /// Private implementation that writes a Yosys-style JSON file to [outPath].
  /// Synchronous version: callers must ensure `topModule.hasBuilt` is true
  /// before calling this method. Throws if validation fails.
  void _exportYosysJson(String outPath) {
    // Validate the ModuleMap hierarchy before exporting to catch issues
    // early and provide a clear error message rather than producing
    // malformed JSON that can crash downstream tools.
    try {
      topMap
        ..validateHierarchy(visited: <Module, List<ModuleMap>>{})
        ..validate();
      final idErrors = topMap.validateIdConnectivity();
      if (idErrors.isNotEmpty) {
        final buf = StringBuffer()..writeln('ID connectivity errors:');
        for (final e in idErrors) {
          buf.writeln('  - $e');
        }
        throw Exception(buf.toString());
      }
    } catch (e) {
      throw StateError('ModuleMap validation failed before export: $e');
    }

    final modulesOut = <String, Map<String, Object?>>{};

    // Use the module's `definitionName` as the stable type key for module
    // definitions and for cell `type` fields so the output matches Yosys
    // semantics where `type` is the module's definition name.

    Map<String, Object?> buildModuleEntryHierarchy(ModuleMap map,
        {bool isTop = false}) {
      final module = map.module;

      // Emit ports (names + directions) but do not attempt to compute bits
      // or connections yet. Combine input/output/inout emission.
      final ports = <String, Map<String, Object?>>{};
      void addPorts(Map<String, Logic> map, String dir) {
        for (final p in map.entries) {
          ports[p.key] = {'direction': dir, 'bits': <int>[]};
        }
      }

      addPorts(module.inputs, 'input');
      addPorts(module.outputs, 'output');
      addPorts(module.inOuts, 'inout');

      // Optionally remove input ports for combinational-like module
      // definitions when those inputs are driven only by Const sources.
      if (filterConstInputsToCombinational &&
          module.definitionName == 'Combinational') {
        module.inputs.forEach((pname, logic) {
          if (logic.srcConnections.isNotEmpty &&
              logic.srcConnections.every((s) => s is Const)) {
            ports.remove(pname);
          }
        });
      }

      // --- STEP 1: Assign IDs to internal nets (child outputs + constants) ---
      //
      // Symmetry principle for understanding the data flow:
      //   Module inputs ↔ Child outputs (both are PRODUCERS in module scope)
      //   Module outputs ↔ Child inputs (both are CONSUMERS in module scope)
      //
      // Producers get fresh IDs allocated here. Consumers look up IDs from
      // their sources via union-find.
      //
      // This map covers:
      // - Child outputs (producers of internal nets) - get fresh IDs
      // - Constants - get fresh IDs
      // - (Module ports are in map.portLogics, also producers)
      final internalNetIds = <Logic, List<Object?>>{};

      // Find the next available ID (after all port IDs)
      final maxPortId = map.portLogics.values
          .expand((ids) => ids)
          .whereType<int>()
          .fold<int>(-1, (m, id) => id > m ? id : m);
      var nextId = maxPortId + 1;

      // Assign IDs to each child's output ports
      for (final childMap in map.submodules.values) {
        final childModule = childMap.module;
        for (final output in childModule.outputs.values) {
          // If this child port is marked global (the child's ModuleMap
          // indicates it), skip allocating internal net IDs so no
          // connectivity/netnames are generated for it.
          if (childMap.globalLogics.contains(output)) {
            continue;
          }
          final ids = List<int>.generate(output.width, (_) => nextId++);
          internalNetIds[output] = ids;
        }
      }

      // Collect constants using the ConstantHandler
      final nextIdRef = [nextId];
      final constHandler = ConstantHandler();
      final constResult = constHandler.collectConstants(
        module: module,
        map: map,
        internalNetIds: internalNetIds,
        ports: ports,
        nextIdRef: nextIdRef,
        isTop: isTop,
        filterConstInputsToCombinational: filterConstInputsToCombinational,
      );
      nextId = nextIdRef[0];

      // Collect pass-through connections and allocate synthetic nets
      final passHandler = PassThroughHandler();
      final passResult = passHandler.collectPassThroughs(
        module: module,
        map: map,
        internalNetIds: internalNetIds,
        ports: ports,
        nextIdRef: nextIdRef,
      );
      final passThroughConnections = passResult.passThroughConnections;
      final syntheticNetsFromPass = passResult.syntheticNets;
      nextId = nextIdRef[0];

      // Merge synthetic nets from pass-through handler into local map used
      // later when emitting netnames and connections.
      final syntheticNets = <String, List<Object?>>{};
      for (final e in syntheticNetsFromPass.entries) {
        syntheticNets[e.key] = e.value;
      }

      // --- STEP 2: Collect transitive closure of intermediate Logics ---
      // Starting from child inputs, trace srcConnections to find all
      // intermediate Logics that connect to sources (module ports, child
      // outputs, or constants). This keeps the scope per-module.
      final intermediateLogics = <Logic>{};
      void collectIntermediates(Logic logic, Set<Logic> visited) {
        if (!visited.add(logic)) {
          return;
        }
        // Skip if already in our ID maps (ports or child outputs)
        if (map.portLogics.containsKey(logic) ||
            internalNetIds.containsKey(logic)) {
          return;
        }
        // Add as intermediate
        intermediateLogics.add(logic);
        // Continue tracing
        for (final src in logic.srcConnections) {
          collectIntermediates(src, visited);
        }
      }

      // Trace from each child input's srcConnections
      for (final childMap in map.submodules.values) {
        for (final input in childMap.module.inputs.values) {
          final visited = <Logic>{};
          for (final src in input.srcConnections) {
            collectIntermediates(src, visited);
          }
        }
      }

      // Also trace from non-LogicStructure module output srcConnections.
      // This finds intermediate Logics between child outputs and module
      // outputs. We skip LogicStructure outputs because their IDs get
      // replaced later by element-based resolution.
      for (final portLogic in map.portLogics.keys) {
        if (module.outputs.values.contains(portLogic) &&
            portLogic is! LogicStructure) {
          final visited = <Logic>{};
          for (final src in portLogic.srcConnections) {
            collectIntermediates(src, visited);
          }
        }
      }

      // --- STEP 3: Build union-find on all Logics ---
      // Collect all Logics: module ports + child outputs + intermediates
      // Note: We intentionally exclude map.internalLogics to avoid using
      // internal signal IDs that may be replaced later (e.g., LogicStructure
      // port IDs get replaced by element-based IDs).
      final allLogics = <Logic>[
        ...map.portLogics.keys,
        ...internalNetIds.keys,
        ...intermediateLogics,
      ];
      final logicIndex = {
        for (var i = 0; i < allLogics.length; i++) allLogics[i]: i
      };

      // Build union pairs from srcConnections/dstConnections
      final cellUnions = <List<int>>[];
      for (var i = 0; i < allLogics.length; i++) {
        final logic = allLogics[i];
        for (final conn in [...logic.srcConnections, ...logic.dstConnections]) {
          final j = logicIndex[conn];
          if (j != null) {
            cellUnions.add([i, j]);
          }
        }
      }

      // Compute connected components
      final cellRoots = computeComponents(allLogics.length, cellUnions);

      // Build root -> canonical IDs mapping. We explicitly prioritize:
      // 1. Module ports (top-level declared Logics with names)
      // 2. Child outputs (internal nets between cells)
      // This ensures module-level signals are used as canonical IDs for their
      // connected components, not intermediate or internal logics.
      final rootToIds = <int, List<Object?>>{};

      // First pass: set canonical IDs from module ports only
      for (final portLogic in map.portLogics.keys) {
        final idx = logicIndex[portLogic];
        if (idx == null) {
          continue;
        }
        final root = cellRoots[idx];
        final ids = map.portLogics[portLogic];
        if (ids != null && ids.isNotEmpty) {
          rootToIds.putIfAbsent(root, () => ids);
        }
      }

      // Second pass: fill in remaining roots from child outputs
      for (final childOutput in internalNetIds.keys) {
        final idx = logicIndex[childOutput];
        if (idx == null) {
          continue;
        }
        final root = cellRoots[idx];
        if (!rootToIds.containsKey(root)) {
          final ids = internalNetIds[childOutput];
          if (ids != null && ids.isNotEmpty) {
            rootToIds[root] = ids;
          }
        }
      }

      // If the PassThroughHandler allocated synthetic internal IDs for a
      // module output that is part of a connected component, prefer those
      // synthetic IDs as the canonical IDs for the component so that the
      // pass-through buffer's Y IDs are used by netnames and consumers.
      for (final e in passThroughConnections.entries) {
        final outLogic = e.key;
        final idx = logicIndex[outLogic];
        if (idx == null) {
          continue;
        }
        final root = cellRoots[idx];
        final synth = internalNetIds[outLogic];
        if (synth != null && synth.isNotEmpty) {
          rootToIds[root] = synth;
        }
      }

      // --- STEP 4: Helper to get IDs for any child port (now a simple lookup)
      // ---
      List<Object?> idsForChildLogic(Logic childLogic) {
        List<Object?> tryFromRootOrMaps(Logic l) {
          final idx = logicIndex[l];
          if (idx != null) {
            return rootToIds[cellRoots[idx]] ??
                map.portLogics[l] ??
                internalNetIds[l] ??
                <Object?>[];
          }
          return map.portLogics[l] ?? internalNetIds[l] ?? <Object?>[];
        }

        // Directly assigned internal net IDs (child outputs / constants)
        if (internalNetIds.containsKey(childLogic)) {
          final idx = logicIndex[childLogic];
          if (idx != null) {
            return rootToIds[cellRoots[idx]] ?? internalNetIds[childLogic]!;
          }
          return internalNetIds[childLogic]!;
        }

        // Check immediate parent sources first (for child inputs)
        for (final src in childLogic.srcConnections) {
          final ids = tryFromRootOrMaps(src);
          if (ids.isNotEmpty) {
            return ids;
          }
        }

        // Then check downstream destinations (for child outputs)
        for (final dst in childLogic.dstConnections) {
          final ids = tryFromRootOrMaps(dst);
          if (ids.isNotEmpty) {
            return ids;
          }
        }

        return <Object?>[];
      }

      // Emit cells with type and connections
      final cells = <String, Map<String, Object?>>{};

      // Track next available internal net ID for synthetic wires
      // Compute max ID from all assigned IDs (port IDs and internal net IDs)
      var nextInternalNetId = 0;
      for (final ids in map.portLogics.values) {
        for (final id in ids) {
          if (id >= nextInternalNetId) {
            nextInternalNetId = id + 1;
          }
        }
      }
      for (final ids in internalNetIds.values) {
        for (final id in ids) {
          if (id is int && id >= nextInternalNetId) {
            nextInternalNetId = id + 1;
          }
        }
      }

      for (final childMap in map.submodules.values) {
        final childModule = childMap.module;
        final cellKey = childModule.hasBuilt
            ? childModule.uniqueInstanceName
            : childModule.name; // instance name (cell key) — keep as-is
        // Default cell type is the child module's definition name.
        final cellType = childModule.definitionName;
        final parameters = <String, Object?>{};

        // Delegate Sequential handling to the refactored SequentialHandler
        final seqHandler = SequentialHandler();
        final handled = seqHandler.handleSequential(
          childModule: childModule,
          ports: childModule.ports,
          internalNetIds: internalNetIds,
          idsForChildLogic: idsForChildLogic,
          cells: cells,
          syntheticNets: syntheticNets,
          nextInternalNetIdGetter: () => nextInternalNetId,
          nextInternalNetIdSetter: (v) => nextInternalNetId = v,
        );
        if (handled) {
          continue;
        }

        // Try exact definitionName mapping first (map true helper modules
        // like 'Swizzle'/'BusSubset' even if they contain small internals).
        // For other cases, only apply the flexible lookup for leaf modules
        // to avoid accidentally matching composite modules like Adders.
        var prim = Primitives.instance
            .lookupByDefinitionName(childModule.definitionName);
        if (prim == null && childMap.submodules.isEmpty) {
          prim = Primitives.instance.lookupForModule(childModule);
        }

        if (prim != null) {
          // For primitives with useRawPortNames (like Add/Combinational), use the
          // actual ROHD port names directly instead of generic A/B/Y names
          if (prim.useRawPortNames) {
            final connMap = <String, List<Object?>>{};
            final portDirs = {
              for (final e in childModule.ports.entries)
                e.value.name: e.value.isInput
                    ? 'input'
                    : e.value.isOutput
                        ? 'output'
                        : 'inout'
            };
            childModule.ports.forEach((_, logic) {
              final ids = idsForChildLogic(logic);
              if (ids.isNotEmpty) {
                connMap[logic.name] = ids;
              }
            });

            // Connectivity check: ensure not all outputs are floating.
            if (childModule.outputs.isNotEmpty) {
              final anyOutputDrives = childModule.outputs.values
                  .any((logic) => idsForChildLogic(logic).isNotEmpty);
              if (!anyOutputDrives) {
                throw StateError(
                    'Submodule ${childModule.uniqueInstanceName} has outputs '
                    'but none drive any nets');
              }
            }

            // Optionally remove ports that are driven only by constants for
            // combinational-like primitives when the dumper option requests
            // const-input filtering.
            if (filterConstInputsToCombinational) {
              if (childModule.definitionName == 'Combinational') {
                connMap.removeWhere((pname, ids) =>
                    ids.isNotEmpty &&
                    ids.whereType<int>().isNotEmpty &&
                    ids
                        .whereType<int>()
                        .every(constResult.blockedIds.contains));
                portDirs.removeWhere((k, _) => !connMap.containsKey(k));
              }
            }

            cells[cellKey] = {
              'hide_name': 0,
              'type': prim.primitiveName,
              'parameters': <String, Object?>{'CLK_POLARITY': 1},
              'attributes': <String, Object?>{},
              'port_directions': portDirs,
              'connections': connMap,
            };
            continue;
          }

          final primCell =
              Primitives.instance.computePrimitiveCell(childModule, prim);

          final portDirs = Map<String, String>.from(
              (primCell['port_directions']! as Map).cast<String, String>());

          // Build the primitive connection map using the centralized helper
          // in the Primitives registry. Provide a small adapter to lookup
          // ROHD-port ids from this dumper's `idsForChildLogic` helper.
          final connMap = Primitives.instance
              .buildPrimitiveConnectionsWithChildLogicLookup(
                  childModule,
                  prim,
                  (primCell['parameters']! as Map).cast<String, Object?>(),
                  portDirs,
                  (m) => map.submodules[m],
                  idsForChildLogic);

          // Connectivity check: ensure not all outputs are floating.
          if (childModule.outputs.isNotEmpty) {
            final anyOutputDrives = childModule.outputs.values
                .any((logic) => idsForChildLogic(logic).isNotEmpty);
            if (!anyOutputDrives) {
              throw StateError(
                  'Submodule ${childModule.uniqueInstanceName} has outputs '
                  'but none drive any nets');
            }
          }

          // Optionally remove const-only ports for combinational primitives
          // when requested. Only apply this filtering for modules whose
          // definitionName is exactly 'Combinational' to avoid affecting
          // comparators and other primitives.
          if (filterConstInputsToCombinational) {
            if (childModule.definitionName == 'Combinational') {
              connMap.removeWhere((pname, ids) =>
                  ids.isNotEmpty &&
                  ids.whereType<int>().isNotEmpty &&
                  ids.whereType<int>().every(constResult.blockedIds.contains));
              portDirs.removeWhere((k, _) => !connMap.containsKey(k));
            }
          }

          cells[cellKey] = {
            'hide_name': 0,
            'type': primCell['type'],
            'parameters': primCell['parameters'],
            'attributes': <String, Object?>{},
            'port_directions': portDirs,
            'connections': connMap,
          };
          continue;
        }

        final connMap = <String, List<Object?>>{};
        final portDirs = {
          for (final e in childModule.ports.entries)
            e.key: e.value.isInput
                ? 'input'
                : e.value.isOutput
                    ? 'output'
                    : 'inout'
        };
        childModule.ports.forEach((pname, logic) {
          final ids = idsForChildLogic(logic);
          if (ids.isNotEmpty) {
            connMap[pname] = ids.cast<Object?>();
          }
        });

        // Connectivity check: ensure not all outputs are floating.
        if (childModule.outputs.isNotEmpty) {
          final anyOutputDrives = childModule.outputs.values
              .any((logic) => idsForChildLogic(logic).isNotEmpty);
          if (!anyOutputDrives) {
            throw StateError(
                'Submodule ${childModule.uniqueInstanceName} has outputs but '
                'none drive any nets');
          }
        }

        cells[cellKey] = {
          'hide_name': 0,
          'type': cellType,
          'parameters': parameters,
          'attributes': <String, Object?>{},
          'port_directions': portDirs,
          'connections': connMap,
        };
      }

      final attr = <String, Object?>{'src': 'generated'};
      if (isTop) {
        attr['top'] = 1;
      }

      // Compute bit-id -> Logic map for this module (for netnames and port
      // bits) Since each Logic now has multiple bit-ids, we map each bit-id to
      // its Logic.
      final bitIdToLogic = <int, Logic>{};
      for (final e in map.portLogics.entries) {
        for (final bitId in e.value) {
          bitIdToLogic[bitId] = e.key;
        }
      }
      for (final e in map.internalLogics.entries) {
        for (final bitId in e.value) {
          bitIdToLogic[bitId] = e.key;
        }
      }
      // Also add child output IDs to the bit->Logic mapping so they appear in
      // netnames. Only numeric bit-ids can be keys in `bitIdToLogic`; string
      // tokens representing constant bit values are not added here and will
      // instead be included directly in netname bit lists when appropriate.
      for (final e in internalNetIds.entries) {
        for (final bitId in e.value) {
          if (bitId is int) {
            bitIdToLogic[bitId] = e.key;
          }
        }
      }

      // Build connectivity across module.signals and compute components
      final signals = List<Logic>.from(module.signals);
      final indexOf = {for (var i = 0; i < signals.length; i++) signals[i]: i};
      final unions = <List<int>>[];
      for (var i = 0; i < signals.length; i++) {
        final s = signals[i];
        for (final conn in [...s.srcConnections, ...s.dstConnections]) {
          final j = indexOf[conn];
          if (j != null) {
            unions.add([i, j]);
          }
        }
      }
      final roots = computeComponents(signals.length, unions);

      // Group bit-ids by component root (using Logic -> root mapping)
      final compToIds = <int, List<Object?>>{};
      for (final entry in bitIdToLogic.entries) {
        final bitId = entry.key;
        final logic = entry.value;
        final idx = indexOf[logic];
        if (idx == null) {
          continue;
        }
        final root = roots[idx];
        compToIds.putIfAbsent(root, () => []).add(bitId);
      }

      // Fill ports.bits and build a mapping from component root -> preferred
      // net name (prefer port names). We'll then ensure every component has
      // a netname entry so cell `connections` ids always reference a net.
      //
      // Each port keeps its own unique IDs. For pass-through connections
      // (output directly connected to input), we'll add explicit buffer cells
      // in the cells section to show the internal wiring.
      final rootToPreferred = <int, String>{};
      final rootToCanonicalIds = <int, List<int>>{};

      // passThroughConnections provided by PassThroughHandler

      // First pass: process INPUT ports to establish canonical IDs
      for (final entry in ports.entries) {
        final pname = entry.key;
        final pdata = entry.value;
        final direction = pdata['direction'] as String?;
        if (direction != 'input') {
          continue;
        }

        final logic = map.module.ports[pname];
        if (logic == null) {
          continue;
        }

        // Input port bit lists are guaranteed to be List<int> from
        // ModuleMap.portLogics. Use them directly.
        final portBitIds = List<int>.from(map.portLogics[logic] ?? <int>[]);
        entry.value['bits'] = portBitIds;

        final idx = indexOf[logic];
        if (idx != null && portBitIds.isNotEmpty) {
          final root = roots[idx];
          rootToPreferred.putIfAbsent(root, () => pname);
          rootToCanonicalIds.putIfAbsent(root, () => portBitIds);
        }
      }

      // Second pass: process OUTPUT ports with their own IDs. Prefer
      // synthetic/internal IDs allocated for pass-throughs when present.
      for (final entry in ports.entries) {
        final pname = entry.key;
        final pdata = entry.value;
        final direction = pdata['direction'] as String?;
        if (direction != 'output') {
          continue;
        }

        final logic = map.module.ports[pname];
        if (logic == null) {
          continue;
        }

        // Normalize to List<int> (port bits must be integers). Prefer
        // synthetic IDs from PassThroughHandler when available; otherwise
        // use ModuleMap-assigned port bits.
        final portBitIds = passThroughConnections.containsKey(logic)
            ? (internalNetIds[logic]?.whereType<int>().toList() ??
                (map.portLogics[logic] ?? <int>[]))
            : (map.portLogics[logic] ?? <int>[]);

        entry.value['bits'] = portBitIds;

        final idx = indexOf[logic];
        if (idx != null && portBitIds.isNotEmpty) {
          final root = roots[idx];
          rootToPreferred.putIfAbsent(root, () => pname);
          rootToCanonicalIds.putIfAbsent(root, () => portBitIds);
        }
      }

      // pass-through detection/allocation handled by PassThroughHandler

      // Third pass: handle inout ports
      for (final entry in ports.entries) {
        final pname = entry.key;
        final pdata = entry.value;
        final direction = pdata['direction'] as String?;
        if (direction == 'input' || direction == 'output') {
          continue;
        }

        final logic = map.module.ports[pname];
        if (logic == null) {
          continue;
        }

        final portBitIds = map.portLogics[logic] ?? <int>[];
        entry.value['bits'] = portBitIds;

        final idx = indexOf[logic];
        if (idx != null && portBitIds.isNotEmpty) {
          final root = roots[idx];
          rootToPreferred.putIfAbsent(root, () => pname);
          rootToCanonicalIds.putIfAbsent(root, () => portBitIds);
        }
      }

      // Add named internal Logic signals to rootToPreferred. Priority is lower
      // than parent ports but higher than child port names. Iterate over all
      // signals from module.signals (already in `signals` list) and add named
      // ones that aren't ports.
      final portLogicsSet = map.portLogics.keys.toSet();
      signals.asMap().entries.where((e) {
        final logic = e.value;
        return !portLogicsSet.contains(logic) &&
            logic.naming != Naming.unnamed &&
            !Naming.isUnpreferred(logic.name);
      }).forEach(
          (e) => rootToPreferred.putIfAbsent(roots[e.key], () => e.value.name));

      // Add buffer cells for pass-through connections (input → output)
      // This makes the internal wiring visible in the schematic. Use the
      // `passThroughNames` map returned by the handler to avoid scanning
      // the module's input/output maps here.
      for (final e in passThroughConnections.entries) {
        final out = e.key;
        final inn = e.value;
        final outName = out.name;
        final inName = passResult.passThroughNames[outName] ?? inn.name;
        final inIds = map.portLogics[inn] ?? <int>[];
        final outIds = internalNetIds[out] ?? map.portLogics[out] ?? <int>[];
        if (inIds.isEmpty || outIds.isEmpty) {
          continue;
        }
        cells['passthrough_${inName}_to_$outName'] = {
          'hide_name': 0,
          'type': r'$buf',
          'parameters': <String, Object?>{'WIDTH': inn.width},
          'attributes': <String, Object?>{},
          'port_directions': <String, String>{'A': 'input', 'Y': 'output'},
          'connections': <String, List<Object?>>{'A': inIds, 'Y': outIds},
        };
      }

      final netnames = <String, Object?>{};

      List<T> uniquePreserve<T>(Iterable<T> items) {
        final seen = <T>{};
        return items.where(seen.add).toList();
      }

      compToIds.forEach((root, ids) {
        final name = rootToPreferred[root] ?? 'net_$root';
        final existing = netnames.putIfAbsent(
                name, () => {'bits': ids, 'attributes': <String, Object?>{}})!
            as Map<String, Object?>;
        final existingBits = (existing['bits']! as List).cast<Object?>();
        existing['bits'] = uniquePreserve<Object?>([...existingBits, ...ids]);
      });

      // Add child output IDs as netnames (internal wires between cells)
      // These IDs connect child outputs to child inputs.
      // Priority: parent port names > named() Logic names > child port names
      // Only add child-derived netnames if the IDs are not already covered
      // by a higher-priority netname.
      //
      // Build a set of IDs already covered by existing netnames (from
      // union-find preferred names which include parent ports and named
      // Logics).
      final coveredIds = <int>{};
      for (final nn in netnames.values) {
        final bits = (nn! as Map<String, Object?>)['bits'] as List?;
        if (bits != null) {
          for (final b in bits) {
            if (b is int) {
              coveredIds.add(b);
            }
          }
        }
      }

      // Add child output IDs as netnames unless already covered by higher-
      // priority netnames. Prefer a connected parent signal name when one
      // exists and is meaningful; otherwise fall back to "<parent>_<port>".
      for (final entry in internalNetIds.entries) {
        final outputLogic = entry.key;
        final ids = entry.value;
        final intIds = ids.whereType<int>().toList();
        if (intIds.isNotEmpty && intIds.every(coveredIds.contains)) {
          continue;
        }

        final preferredName =
            outputLogic.dstConnections.cast<Logic?>().firstWhere((l) {
          if (l == null) {
            return false;
          }
          final idx = indexOf[l];
          return idx != null &&
              l.naming != Naming.unnamed &&
              !Naming.isUnpreferred(l.name);
        }, orElse: () => null)?.name;

        final netName = (preferredName != null &&
                !netnames.containsKey(preferredName))
            ? preferredName
            : '${outputLogic.parentModule?.uniqueInstanceName ?? 'unknown'}_'
                '${outputLogic.name}';

        if (!netnames.containsKey(netName)) {
          netnames[netName] = <String, Object?>{
            'bits': ids,
            'attributes': <String, Object?>{}
          };
          intIds.forEach(coveredIds.add);
        }
      }

      // Merge synthetic nets created during Sequential expansion when absent
      syntheticNets.forEach((name, ids) {
        netnames.putIfAbsent(
            name, () => {'bits': ids, 'attributes': <String, Object?>{}});
      });

      // Attempt element-based resolution for LogicStructure module outputs.
      // If a module output is a LogicStructure, try to build its bitlist from
      // child outputs that are structures or from direct element producers.
      for (final outEntry in module.outputs.entries) {
        final outName = outEntry.key;
        final outLogic = outEntry.value;
        if (outLogic is! LogicStructure) {
          continue;
        }

        final struct = outLogic;
        final combined = <Object?>[];
        var allFound = true;

        List<Object?>? findElemIds(Logic elem) {
          // Direct child output mapping
          if (internalNetIds.containsKey(elem)) {
            return internalNetIds[elem];
          }

          // Direct canonical match (same canonical logic)
          for (final e in internalNetIds.entries) {
            if (identical(getCanonicalLogic(e.key), getCanonicalLogic(elem))) {
              return e.value;
            }
          }

          // If a child exported a full LogicStructure, slice its ids
          for (final e in internalNetIds.entries) {
            if (e.key is! LogicStructure) {
              continue;
            }
            final childStruct = e.key as LogicStructure;
            // Find the index of the matching child element and compute its
            // bit offset by summing widths of preceding elements.
            final idx = childStruct.elements.indexWhere((childElem) =>
                identical(childElem, elem) ||
                identical(
                    getCanonicalLogic(childElem), getCanonicalLogic(elem)));
            if (idx == -1) {
              continue;
            }
            final bitOffset = childStruct.elements
                .take(idx)
                .fold<int>(0, (s, el) => s + el.width);
            final childElemWidth = childStruct.elements[idx].width;
            final ids = e.value;
            if (ids.length >= bitOffset + childElemWidth) {
              final elemIds =
                  ids.sublist(bitOffset, bitOffset + childElemWidth);
              internalNetIds[elem] = List<Object?>.from(elemIds);
              return elemIds;
            }
          }

          // Fall back: check module-level port or internal mapping
          return map.portLogics[elem] ?? map.internalLogics[elem];
        }

        final elemLists = struct.elements.map(findElemIds).toList();
        if (elemLists.any((l) => l == null)) {
          allFound = false;
        } else {
          combined.addAll(elemLists.expand((l) => l!));
        }

        if (allFound && combined.length == struct.width) {
          // Replace the port bits and create a netname so viewers show
          // the module output connected to upstream producers.
          ports[outName] = {
            'direction': 'output',
            'bits': List<Object?>.from(combined),
          };
          netnames[outName] = {
            'bits': List<Object?>.from(combined),
            'attributes': <String, Object?>{},
          };
        }
      }

      // Add const netnames (per-input and pattern-level) using ConstantHandler
      // so constant handling logic is consolidated in one place.
      constHandler.emitConstNetnames(
        constResult: constResult,
        netnames: netnames,
      );
      // Create $const driver cells using the ConstantHandler
      final referencedIds = <int>{
        ...ports.values
            .expand((p) => (p['bits']! as List<Object?>).cast<int>()),
        ...cells.values
            .where((c) => c['type'] != r'$const')
            .map((c) => c['connections'] as Map<String, dynamic>?)
            .where((conns) => conns != null)
            .expand((conns) => conns!.values
                .whereType<List<Object?>>()
                .expand((l) => l)
                .whereType<int>()),
      };

      constHandler.emitConstCells(
        constResult: constResult,
        cells: cells,
        referencedIds: referencedIds,
      );

      return {
        'attributes': attr,
        'ports': ports,
        'cells': cells,
        'netnames': netnames,
      };
    }

    // Walk module tree and emit hierarchy entries. Use the module's type
    // name (`module.name`) as the key so all instances of the same type
    // share the same module definition (Yosys-style).
    // Skip modules that are primitives - they don't need module definitions.
    void walkHierarchy(ModuleMap map, {bool isTop = false}) {
      final typeName = map.module.definitionName;

      // Check if this module is a primitive - if so, don't emit a module
      // definition.
      final prim = Primitives.instance.lookupForModule(map.module);
      if (prim != null) {
        // Primitives don't get module definitions - they're handled by
        // port_directions in cells.
        return;
      }

      if (!modulesOut.containsKey(typeName)) {
        modulesOut[typeName] = buildModuleEntryHierarchy(map, isTop: isTop);
      } else {
        // Merge ports from this instance into the existing module definition
        // This handles cases where different instances have different optional
        // ports.
        final existing = modulesOut[typeName]!;
        final existingPorts = existing['ports'] as Map<String, dynamic>? ?? {};
        final module = map.module;

        for (final name in module.inputs.keys) {
          existingPorts.putIfAbsent(
              name, () => {'direction': 'input', 'bits': <int>[]});
        }
        for (final name in module.outputs.keys) {
          existingPorts.putIfAbsent(
              name, () => {'direction': 'output', 'bits': <int>[]});
        }
        for (final name in module.inOuts.keys) {
          existingPorts.putIfAbsent(
              name, () => {'direction': 'inout', 'bits': <int>[]});
        }
      }
      map.submodules.values.forEach(walkHierarchy);
    }

    walkHierarchy(topMap, isTop: true);

    final out = {
      'creator': 'SchematicDumper (rohd_hcl)',
      'modules': modulesOut
    };

    // (Diagnostics removed.)
    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  }

  /// Synchronous accessor for the top module map.
  ModuleMap get moduleMap => topMap;

  /// Public export helper. Call this to write a Yosys-style JSON file to
  /// [outPath]. The constructor no longer triggers automatic exports.
  /// Synchronous export. Throws if `topModule.hasBuilt` is false.
  void exportYosysJson(String outPath) {
    if (!topModule.hasBuilt) {
      throw StateError('Top module must be built before exporting JSON');
    }
    _exportYosysJson(outPath);
  }
}
