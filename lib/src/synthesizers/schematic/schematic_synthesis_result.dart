// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_synthesis_result.dart
// Synthesis result for schematic generation.
//
// 2025 December 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic.dart';

/// A [SynthesisResult] representing schematic output for a single [Module].
///
/// Contains ports, cells (child instances), and netnames for one level of
/// module hierarchy. The [SynthBuilder] handles recursion across submodules.
class SchematicSynthesisResult extends SynthesisResult {
  /// The ports map: name → {direction, bits}.
  final Map<String, Map<String, Object?>> ports;

  /// The cells map: instance name → cell data.
  final Map<String, Map<String, Object?>> cells;

  /// The netnames map: net name → {bits, attributes}.
  final Map<String, Object?> netnames;

  /// Attributes for this module (e.g., top marker).
  final Map<String, Object?> attributes;

  /// Cached JSON string for comparison and output.
  late final String _cachedJson = _buildJson();

  /// Creates a [SchematicSynthesisResult] for [module].
  SchematicSynthesisResult(
    super.module,
    super.getInstanceTypeOfModule, {
    required this.ports,
    required this.cells,
    required this.netnames,
    this.attributes = const {},
  });

  String _buildJson() {
    final moduleEntry = <String, Object?>{
      'attributes': attributes,
      'ports': ports,
      'cells': cells,
      'netnames': netnames,
    };
    return const JsonEncoder().convert(moduleEntry);
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SchematicSynthesisResult && _cachedJson == other._cachedJson;

  @override
  int get matchHashCode => _cachedJson.hashCode;

  @override
  @Deprecated('Use `toSynthFileContents()` instead.')
  String toFileContents() => toSynthFileContents().first.contents;

  @override
  List<SynthFileContents> toSynthFileContents() {
    // Use instanceTypeName (uniquified by SynthBuilder) instead of
    // module.definitionName to match SystemVerilog synthesizer behavior
    final typeName = instanceTypeName;
    // Produce a JSON file for this module definition
    final moduleEntry = <String, Object?>{
      'attributes': attributes,
      'ports': ports,
      'cells': cells,
      'netnames': netnames,
    };
    final contents = const JsonEncoder.withIndent('  ').convert({
      'creator': 'SchematicSynthesizer (rohd)',
      'modules': {typeName: moduleEntry},
    });
    return [
      SynthFileContents(
        name: '$typeName.rohd.json',
        description: 'Schematic for $typeName',
        contents: contents,
      ),
    ];
  }
}

/// Factory helper to build [SchematicSynthesisResult] from a [ModuleMap].
///
/// This extracts the logic from SchematicDumper.buildModuleEntryHierarchy to
/// handle one module level without recursion.
class SchematicSynthesisResultBuilder {
  /// The module to synthesize.
  final Module module;

  /// The ModuleMap for this module.
  final ModuleMap map;

  /// Whether to filter const-only inputs to combinational primitives.
  final bool filterConstInputsToCombinational;

  /// Function to get instance type names for submodules.
  final String Function(Module) getInstanceTypeOfModule;

  /// Creates a builder for [module].
  SchematicSynthesisResultBuilder({
    required this.module,
    required this.map,
    required this.getInstanceTypeOfModule,
    this.filterConstInputsToCombinational = false,
  });

  /// Builds the [SchematicSynthesisResult].
  SchematicSynthesisResult build({bool isTop = false}) {
    // Build ports, cells, netnames for this one module level.
    final ports = <String, Map<String, Object?>>{};
    final cells = <String, Map<String, Object?>>{};
    final netnames = <String, Object?>{};
    final attr = <String, Object?>{'src': 'generated'};
    if (isTop) {
      attr['top'] = 1;
    }

    // Emit ports (names + directions)
    void addPorts(Map<String, Logic> portMap, String dir) {
      for (final p in portMap.entries) {
        ports[p.key] = {'direction': dir, 'bits': <int>[]};
      }
    }

    addPorts(module.inputs, 'input');
    addPorts(module.outputs, 'output');
    addPorts(module.inOuts, 'inout');

    // Assign IDs to internal nets (child outputs + constants)
    final internalNetIds = <Logic, List<Object?>>{};
    final maxPortId = map.portLogics.values
        .expand((ids) => ids)
        .whereType<int>()
        .fold<int>(-1, (m, id) => id > m ? id : m);
    var nextId = maxPortId + 1;

    // Assign IDs to each child's output ports
    for (final childMap in map.submodules.values) {
      final childModule = childMap.module;
      for (final output in childModule.outputs.values) {
        if (childMap.globalLogics.contains(output)) {
          continue;
        }
        final ids = List<int>.generate(output.width, (_) => nextId++);
        internalNetIds[output] = ids;
      }
    }

    // Collect constants
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

    // Collect pass-through connections
    final passHandler = PassThroughHandler();
    final passResult = passHandler.collectPassThroughs(
      module: module,
      map: map,
      internalNetIds: internalNetIds,
      ports: ports,
      nextIdRef: nextIdRef,
    );
    nextId = nextIdRef[0];

    final syntheticNets = <String, List<Object?>>{};
    for (final e in passResult.syntheticNets.entries) {
      syntheticNets[e.key] = e.value;
    }

    // Collect intermediate logics
    final intermediateLogics = <Logic>{};
    void collectIntermediates(Logic logic, Set<Logic> visited) {
      if (!visited.add(logic)) {
        return;
      }
      if (map.portLogics.containsKey(logic) ||
          internalNetIds.containsKey(logic)) {
        return;
      }
      intermediateLogics.add(logic);
      for (final src in logic.srcConnections) {
        collectIntermediates(src, visited);
      }
    }

    for (final childMap in map.submodules.values) {
      for (final input in childMap.module.inputs.values) {
        final visited = <Logic>{};
        for (final src in input.srcConnections) {
          collectIntermediates(src, visited);
        }
      }
    }

    for (final portLogic in map.portLogics.keys) {
      if (module.outputs.values.contains(portLogic) &&
          portLogic is! LogicStructure) {
        final visited = <Logic>{};
        for (final src in portLogic.srcConnections) {
          collectIntermediates(src, visited);
        }
      }
    }

    // Build union-find on all Logics
    final allLogics = <Logic>[
      ...map.portLogics.keys,
      ...internalNetIds.keys,
      ...intermediateLogics,
    ];
    final logicIndex = {
      for (var i = 0; i < allLogics.length; i++) allLogics[i]: i
    };

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

    final cellRoots = computeComponents(allLogics.length, cellUnions);

    // Build root → canonical IDs mapping
    final rootToIds = <int, List<Object?>>{};

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

    for (final e in passResult.passThroughConnections.entries) {
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

    // Helper to get IDs for any child port
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

      if (internalNetIds.containsKey(childLogic)) {
        final idx = logicIndex[childLogic];
        if (idx != null) {
          return rootToIds[cellRoots[idx]] ?? internalNetIds[childLogic]!;
        }
        return internalNetIds[childLogic]!;
      }

      for (final src in childLogic.srcConnections) {
        final ids = tryFromRootOrMaps(src);
        if (ids.isNotEmpty) {
          return ids;
        }
      }

      for (final dst in childLogic.dstConnections) {
        final ids = tryFromRootOrMaps(dst);
        if (ids.isNotEmpty) {
          return ids;
        }
      }

      return <Object?>[];
    }

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

    // Emit cells
    for (final childMap in map.submodules.values) {
      final childModule = childMap.module;
      final cellKey = childModule.hasBuilt
          ? childModule.uniqueInstanceName
          : childModule.name;

      // Check if module uses Schematic mixin with custom cell generation
      if (childModule is Schematic) {
        final instanceType = getInstanceTypeOfModule(childModule);
        final cellDef = childModule.schematicCell(
          instanceType,
          cellKey,
          childModule.ports,
        );

        if (cellDef != null) {
          // Use custom cell definition from mixin
          final connMap = <String, List<Object?>>{};
          childModule.ports.forEach((pname, logic) {
            final ids = idsForChildLogic(logic);
            if (ids.isNotEmpty) {
              connMap[pname] = ids.cast<Object?>();
            }
          });

          cells[cellKey] = {
            'hide_name': 0,
            'type': cellDef.type,
            'parameters': cellDef.parameters,
            'attributes': cellDef.attributes,
            'port_directions': cellDef.portDirections.isNotEmpty
                ? cellDef.portDirections
                : {
                    for (final e in childModule.ports.entries)
                      e.key: e.value.isInput
                          ? 'input'
                          : e.value.isOutput
                              ? 'output'
                              : 'inout'
                  },
            'connections': connMap,
          };
          continue;
        }

        // If schematicCell returns null but isSchematicPrimitive is true,
        // fall through to primitive handling
        if (childModule.isSchematicPrimitive) {
          final prim = Primitives.instance.lookupForModule(childModule);
          if (prim != null) {
            _emitPrimitiveCell(
              childModule: childModule,
              childMap: childMap,
              cellKey: cellKey,
              prim: prim,
              cells: cells,
              idsForChildLogic: idsForChildLogic,
              constResult: constResult,
              syntheticNets: syntheticNets,
              nextInternalNetIdGetter: () => nextInternalNetId,
              nextInternalNetIdSetter: (v) => nextInternalNetId = v,
              internalNetIds: internalNetIds,
            );
            continue;
          }
        }
      }

      // Check if this is a primitive - if so, skip emitting a module instance
      // and instead emit the primitive cell directly
      final prim = Primitives.instance.lookupForModule(childModule);
      if (prim != null) {
        // Handle primitive cells
        _emitPrimitiveCell(
          childModule: childModule,
          childMap: childMap,
          cellKey: cellKey,
          prim: prim,
          cells: cells,
          idsForChildLogic: idsForChildLogic,
          constResult: constResult,
          syntheticNets: syntheticNets,
          nextInternalNetIdGetter: () => nextInternalNetId,
          nextInternalNetIdSetter: (v) => nextInternalNetId = v,
          internalNetIds: internalNetIds,
        );
        continue;
      }

      // Non-primitive module instance - use the instance type from SynthBuilder
      final instanceType = getInstanceTypeOfModule(childModule);

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

      cells[cellKey] = {
        'hide_name': 0,
        'type': instanceType,
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': portDirs,
        'connections': connMap,
      };
    }

    // Build netnames from component IDs
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
    for (final e in internalNetIds.entries) {
      for (final bitId in e.value) {
        if (bitId is int) {
          bitIdToLogic[bitId] = e.key;
        }
      }
    }

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

    final rootToPreferred = <int, String>{};
    final rootToCanonicalIds = <int, List<int>>{};

    // Process INPUT ports
    for (final entry in ports.entries) {
      final pname = entry.key;
      final direction = entry.value['direction'] as String?;
      if (direction != 'input') {
        continue;
      }

      final logic = module.ports[pname];
      if (logic == null) {
        continue;
      }

      final portBitIds = List<int>.from(map.portLogics[logic] ?? <int>[]);
      entry.value['bits'] = portBitIds;

      final idx = indexOf[logic];
      if (idx != null && portBitIds.isNotEmpty) {
        final root = roots[idx];
        rootToPreferred.putIfAbsent(root, () => pname);
        rootToCanonicalIds.putIfAbsent(root, () => portBitIds);
      }
    }

    // Process OUTPUT ports
    for (final entry in ports.entries) {
      final pname = entry.key;
      final direction = entry.value['direction'] as String?;
      if (direction != 'output') {
        continue;
      }

      final logic = module.ports[pname];
      if (logic == null) {
        continue;
      }

      final portBitIds = passResult.passThroughConnections.containsKey(logic)
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

    // Process INOUT ports
    for (final entry in ports.entries) {
      final pname = entry.key;
      final direction = entry.value['direction'] as String?;
      if (direction == 'input' || direction == 'output') {
        continue;
      }

      final logic = module.ports[pname];
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

    // Add named internal signals to rootToPreferred
    final portLogicsSet = map.portLogics.keys.toSet();
    signals.asMap().entries.where((e) {
      final logic = e.value;
      return !portLogicsSet.contains(logic) &&
          logic.naming != Naming.unnamed &&
          !Naming.isUnpreferred(logic.name);
    }).forEach(
        (e) => rootToPreferred.putIfAbsent(roots[e.key], () => e.value.name));

    // Add buffer cells for pass-through connections
    for (final e in passResult.passThroughConnections.entries) {
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

    // Add child output IDs as netnames
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

      final netName =
          (preferredName != null && !netnames.containsKey(preferredName))
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

    syntheticNets.forEach((name, ids) {
      netnames.putIfAbsent(
          name, () => {'bits': ids, 'attributes': <String, Object?>{}});
    });

    // Handle LogicStructure module outputs
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
        if (internalNetIds.containsKey(elem)) {
          return internalNetIds[elem];
        }

        for (final e in internalNetIds.entries) {
          if (identical(_getCanonicalLogic(e.key), _getCanonicalLogic(elem))) {
            return e.value;
          }
        }

        for (final e in internalNetIds.entries) {
          if (e.key is! LogicStructure) {
            continue;
          }
          final childStruct = e.key as LogicStructure;
          final idx = childStruct.elements.indexWhere((childElem) =>
              identical(childElem, elem) ||
              identical(
                  _getCanonicalLogic(childElem), _getCanonicalLogic(elem)));
          if (idx == -1) {
            continue;
          }
          final bitOffset = childStruct.elements
              .take(idx)
              .fold<int>(0, (s, el) => s + el.width);
          final childElemWidth = childStruct.elements[idx].width;
          final ids = e.value;
          if (ids.length >= bitOffset + childElemWidth) {
            final elemIds = ids.sublist(bitOffset, bitOffset + childElemWidth);
            internalNetIds[elem] = List<Object?>.from(elemIds);
            return elemIds;
          }
        }

        return map.portLogics[elem] ?? map.internalLogics[elem];
      }

      final elemLists = struct.elements.map(findElemIds).toList();
      if (elemLists.any((l) => l == null)) {
        allFound = false;
      } else {
        combined.addAll(elemLists.expand((l) => l!));
      }

      if (allFound && combined.length == struct.width) {
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

    // Add const netnames
    constHandler.emitConstNetnames(
      constResult: constResult,
      netnames: netnames,
    );

    // Create $const driver cells
    final referencedIds = <int>{
      ...ports.values.expand((p) => (p['bits']! as List<Object?>).cast<int>()),
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

    return SchematicSynthesisResult(
      module,
      getInstanceTypeOfModule,
      ports: ports,
      cells: cells,
      netnames: netnames,
      attributes: attr,
    );
  }

  /// Emits a primitive cell into [cells].
  void _emitPrimitiveCell({
    required Module childModule,
    required ModuleMap childMap,
    required String cellKey,
    required PrimitiveDescriptor prim,
    required Map<String, Map<String, Object?>> cells,
    required List<Object?> Function(Logic) idsForChildLogic,
    required ConstantCollectionResult constResult,
    required Map<String, List<Object?>> syntheticNets,
    required int Function() nextInternalNetIdGetter,
    required void Function(int) nextInternalNetIdSetter,
    required Map<Logic, List<Object?>> internalNetIds,
  }) {
    // Handle Sequential modules
    final seqHandler = SequentialHandler();
    final handled = seqHandler.handleSequential(
      childModule: childModule,
      ports: childModule.ports,
      internalNetIds: internalNetIds,
      idsForChildLogic: idsForChildLogic,
      cells: cells,
      syntheticNets: syntheticNets,
      nextInternalNetIdGetter: nextInternalNetIdGetter,
      nextInternalNetIdSetter: nextInternalNetIdSetter,
    );
    if (handled) {
      return;
    }

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

      if (filterConstInputsToCombinational &&
          childModule.definitionName == 'Combinational') {
        connMap.removeWhere((pname, ids) =>
            ids.isNotEmpty &&
            ids.whereType<int>().isNotEmpty &&
            ids.whereType<int>().every(constResult.blockedIds.contains));
        portDirs.removeWhere((k, _) => !connMap.containsKey(k));
      }

      cells[cellKey] = {
        'hide_name': 0,
        'type': prim.primitiveName,
        'parameters': <String, Object?>{'CLK_POLARITY': 1},
        'attributes': <String, Object?>{},
        'port_directions': portDirs,
        'connections': connMap,
      };
      return;
    }

    final primCell =
        Primitives.instance.computePrimitiveCell(childModule, prim);
    final portDirs = Map<String, String>.from(
        (primCell['port_directions']! as Map).cast<String, String>());

    final connMap = Primitives.instance
        .buildPrimitiveConnectionsWithChildLogicLookup(
            childModule,
            prim,
            (primCell['parameters']! as Map).cast<String, Object?>(),
            portDirs,
            (m) => map.submodules[m],
            idsForChildLogic);

    if (filterConstInputsToCombinational &&
        childModule.definitionName == 'Combinational') {
      connMap.removeWhere((pname, ids) =>
          ids.isNotEmpty &&
          ids.whereType<int>().isNotEmpty &&
          ids.whereType<int>().every(constResult.blockedIds.contains));
      portDirs.removeWhere((k, _) => !connMap.containsKey(k));
    }

    cells[cellKey] = {
      'hide_name': 0,
      'type': primCell['type'],
      'parameters': primCell['parameters'],
      'attributes': <String, Object?>{},
      'port_directions': portDirs,
      'connections': connMap,
    };
  }
}

/// Helper to get canonical Logic following srcConnection chain.
Logic _getCanonicalLogic(Logic logic) {
  var cur = logic;
  final visited = <int>{};
  while (cur.srcConnection != null && !visited.contains(cur.hashCode)) {
    visited.add(cur.hashCode);
    cur = cur.srcConnection!;
  }
  return cur;
}
