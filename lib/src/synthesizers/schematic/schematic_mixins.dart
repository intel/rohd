// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_mixins.dart
// Definition for Schematic Mixins for controlling schematic synthesis.
//
// 2025 December 20
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Architecture Overview:
//
// The schematic synthesis system uses a mixin-first architecture where modules
// can control their schematic representation. There are several approaches:
//
// 1. **Core ROHD modules** (And2Gate, Or2Gate, etc.):
//    - NOT modified with mixins
//    - Registered in CoreGatePrimitives by runtime type
//    - Example: CoreGatePrimitives.register(And2Gate, descriptor)
//
// 2. **Simple user primitives**:
//    - Use PrimitiveSchematic mixin
//    - Override primitiveDescriptor() to provide descriptor
//    - Automatic port mapping and parameter inference
//
// 3. **Inline primitives**:
//    - Use InlineSchematic mixin
//    - Override schematicPrimitiveName and optionally schematicParameters
//    - Good for simple wrappers with fixed primitive types
//
// 4. **Complex primitives** (like Sequential):
//    - Use Schematic mixin directly
//    - Override primitiveDescriptor() and/or emitSchematicCells()
//    - Full control over cell emission (can emit multiple cells)
//
// 5. **Custom modules** (rare):
//    - Use Schematic mixin
//    - Override schematicCell() for custom instantiation
//    - Or schematicDefinition() for custom module definitions

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/module_utils.dart';
import 'package:rohd/src/synthesizers/schematic/schematic_gates.dart';
import 'package:rohd/src/synthesizers/schematic/schematic_synthesis_result.dart';

/// Descriptor describing how a ROHD helper module maps to a Yosys
/// primitive type.
class PrimitiveDescriptor {
  /// The Yosys primitive type name (e.g. "\\$concat", "\\$dff", "\\$mux").
  final String primitiveName;

  /// Map from the ROHD module's port name to the primitive port name.
  final Map<String, String> portMap;

  /// Map of primitive parameter name -> ROHD port name or expression key.
  final Map<String, String> paramFromPort;

  /// Optional primitive port directions (primitive port ->
  /// 'input'|'output'|'inout'). When provided in a descriptor, these directions
  /// are used directly and the automatic direction inference is skipped for
  /// those ports.
  final Map<String, String> portDirs;

  /// Default parameter values supplied by the descriptor (applied before
  /// inference). Use this to move always-1 defaults into registration.
  final Map<String, Object?> defaultParams;

  /// When true, use the ROHD module's actual port names directly instead of
  /// generating generic A/B/Y names. Useful for modules like Sequential that
  /// have dynamic port names per instance.
  final bool useRawPortNames;

  /// Creates a [PrimitiveDescriptor] for leaf schematic primitive mapping.
  const PrimitiveDescriptor(
      {required this.primitiveName,
      this.portMap = const {},
      this.paramFromPort = const {},
      this.portDirs = const {},
      this.defaultParams = const {},
      this.useRawPortNames = false});
}

/// Helper methods for primitive cell computation and connection mapping.
///
/// These static methods provide the core logic for mapping ROHD modules to
/// schematic primitives, including parameter inference and port mapping.
class PrimitiveHelper {
  PrimitiveHelper._();

  /// Compute the primitive cell representation for a `Module` that maps to
  /// a known primitive descriptor. Returns a map containing keys:
  /// - 'type' -> String primitive type (e.g. r'$concat')
  /// - 'parameters' -> `Map<String,Object?> `of parameter values
  /// - 'port_directions' -> `Map<String,String>` mapping primitive port names
  ///    to directions expected by the loader ('input'/'output'/'inout')
  static Map<String, Object?> computePrimitiveCell(
      Module childModule, PrimitiveDescriptor prim) {
    final cellType = prim.primitiveName;
    final parameters = <String, Object?>{};
    // Apply any descriptor-provided default parameters before inference.
    // This lets registrations move always-1 (or other) defaults into the
    // descriptor so they don't need to be inferred here.
    if (prim.defaultParams.isNotEmpty) {
      parameters.addAll(prim.defaultParams);
    }

    void ensureIntParam(String k, int defaultVal) {
      final v = parameters[k];
      if (v is int) {
        if (v <= 0) {
          parameters[k] = defaultVal;
        }
      } else {
        parameters[k] = defaultVal;
      }
    }

    ensureIntParam('A_WIDTH', 1);
    ensureIntParam('B_WIDTH', 1);
    ensureIntParam('Y_WIDTH', 1);
    if (parameters['OFFSET'] == null) {
      parameters['OFFSET'] = 0;
    }

    final ywVal = parameters['Y_WIDTH'];
    if ((parameters['HIGH'] == null || parameters['LOW'] == null) &&
        ywVal is int) {
      parameters['LOW'] = 0;
      parameters['HIGH'] = (ywVal - 1) >= 0 ? (ywVal - 1) : 0;
    }

    // Initialize `portDirs` from the descriptor.
    final portDirs = <String, String>{}..addAll(prim.portDirs);

    return {
      'type': cellType,
      'parameters': parameters,
      'port_directions': portDirs,
    };
  }

  /// Finalize/adjust primitive parameters using the connection map built by
  /// the dumper. This allows inference that depends on actual bit-id
  /// connections (for example, determining slice offsets/high/low and
  /// input widths) rather than only on port names or descriptor defaults.
  ///
  /// - [childModule] is the module instance for the primitive.
  /// - [prim] is the primitive descriptor.
  /// - [parameters] is the mutable parameters map produced by
  ///   `computePrimitiveCell` (will be modified in-place).
  /// - [connMap] maps primitive port names (A/B/Y/etc) to lists of bit ids
  ///   (as produced by the dumper's connection resolution). Bit ids may be
  ///   integers (net ids) or string tokens for constants.
  static void finalizePrimitiveCell(
      Module childModule,
      PrimitiveDescriptor prim,
      Map<String, Object?> parameters,
      Map<String, List<Object?>> connMap) {
    // Apply simple paramFromPort mappings (e.g., A_WIDTH -> A)
    prim.paramFromPort.entries
        .where((e) => e.key.endsWith('_WIDTH'))
        .forEach((e) {
      final bits = connMap[e.value];
      if (bits != null) {
        parameters[e.key] = bits.length;
      }
    });

    // Specialized handling for $slice (BusSubset) primitives. Compute
    // OFFSET/HIGH/LOW/Y_WIDTH/A_WIDTH when we have concrete connection ids
    // for the source ('A') and the result ('Y').
    if (prim.primitiveName == r'$slice') {
      final aBits = connMap['A'] ?? <Object?>[];
      final yBits = connMap['Y'] ?? <Object?>[];

      // Populate widths if available
      if (aBits.isNotEmpty) {
        parameters['A_WIDTH'] = aBits.length;
      }
      if (yBits.isNotEmpty) {
        parameters['Y_WIDTH'] = yBits.length;
      }

      // For offset/high/low we need integer net ids to compute positions
      final aInts = aBits.whereType<int>().toList()..sort();
      final yInts = yBits.whereType<int>().toList()..sort();

      if (aInts.isNotEmpty && yInts.isNotEmpty) {
        // Build index map from A net id -> position within A (0-based)
        final aIndex = <int, int>{};
        for (var i = 0; i < aInts.length; i++) {
          aIndex[aInts[i]] = i;
        }

        // Map each Y net id to its index in A; require that all Y ids exist
        // within A to compute a contiguous OFFSET/HIGH/LOW. If not present,
        // fall back to conservative defaults.
        final mappedCandidates = yInts.map((yId) => aIndex[yId]).toList();
        final allMapped = mappedCandidates.every((e) => e != null);
        final mappedIndices =
            allMapped ? mappedCandidates.cast<int>().toList() : <int>[];

        if (allMapped && mappedIndices.isNotEmpty) {
          mappedIndices.sort();
          final low = mappedIndices.first;
          final high = mappedIndices.last;
          parameters['OFFSET'] = low;
          parameters['LOW'] = low;
          parameters['HIGH'] = high;
          parameters['Y_WIDTH'] = mappedIndices.length;
          parameters['A_WIDTH'] = aInts.length;
        }
        // If connection-based mapping failed to determine offsets, try a
        // fallback: parse output names for `_subset_HIGH_LOW` patterns which
        // ROHD may emit for BusSubset outputs. This preserves previous
        // behavior that relied on naming heuristics when structural mapping
        // is not straightforward.
        if ((parameters['LOW'] == null ||
                parameters['HIGH'] == null ||
                (parameters['LOW'] is int &&
                    parameters['LOW'] == 0 &&
                    parameters['HIGH'] is int &&
                    parameters['HIGH'] == 0)) &&
            childModule.outputs.isNotEmpty) {
          final re = RegExp(r'_subset_(\d+)_(\d+)');
          final match = childModule.outputs.keys
              .map(re.firstMatch)
              .firstWhere((m) => m != null, orElse: () => null);
          if (match != null) {
            final hi = int.parse(match.group(1)!);
            final lo = int.parse(match.group(2)!);
            final low = hi < lo ? hi : lo;
            final high = hi < lo ? lo : hi;
            parameters['LOW'] = low;
            parameters['HIGH'] = high;
            parameters['OFFSET'] = low;
            parameters['Y_WIDTH'] = (high - low) + 1;
          }
        }
      }
    }

    // For $concat (concat/swizzle), derive input widths from mapped ports
    if (prim.primitiveName == r'$concat') {
      // Common placeholders A/B may represent inputs; if present, set widths
      if (connMap.containsKey('A')) {
        parameters['A_WIDTH'] = connMap['A']!.length;
      }
      if (connMap.containsKey('B')) {
        parameters['B_WIDTH'] = connMap['B']!.length;
      }
      // Update Y width as sum if A/B provided
      final aW = parameters['A_WIDTH'];
      final bW = parameters['B_WIDTH'];
      if (aW is int && bW is int) {
        parameters['Y_WIDTH'] = aW + bW;
      }
    }
  }

  /// Deterministically map ROHD port names to primitive port names.
  ///
  /// Returns a map where the key is the ROHD port name and the value is the
  /// corresponding primitive port name. The mapping rules are:
  /// 1. If the descriptor's `portMap` provides a literal ROHD name for a
  ///    primitive port and that ROHD port exists, use it.
  /// 2. Group placeholder mappings (single-letter placeholders like 'A', 'B')
  ///    and map remaining ROHD ports in deterministic sorted order to the
  ///    placeholder-named primitive ports (sorted).
  /// 3. Any remaining primitive ports are assigned positionally to remaining
  ///    ROHD ports in sorted order.
  static Map<String, String> mapRohdToPrimitivePorts(PrimitiveDescriptor prim,
      Module childModule, Map<String, String> portDirs) {
    final rohdInputs = childModule.inputs.keys.toList()..sort();
    final rohdOutputs = childModule.outputs.keys.toList()..sort();
    final rohdInouts = childModule.inOuts.keys.toList()..sort();

    // Normalize prim.portMap: it may be registered in either direction
    // (primPort -> rohdName) or (rohdName -> primPort). Detect which form
    // is used and build a `primToRohd` map. Build the set of primitive port
    // names from both the explicit `portDirs` and any keys present in the
    // descriptor's `portMap` so registrations may omit input entries and
    // only declare outputs/inouts if desired. Missing directions default to
    // 'input' during mapping below.
    final primPortNames = <String>{}
      ..addAll(portDirs.keys)
      ..addAll(prim.portMap.keys);
    final rohdPortNames = childModule.ports.keys.toSet();

    // Build mapping candidates: for each primitive port, collect either a
    // literal mapping or a deterministic list of ROHD names matching a
    // regex. We will consume these lists deterministically when assigning
    // ROHD ports so regex matches are not accidentally reused or picked
    // nondeterministically by different prim ports.
    final primToRohdLists = <String, List<String>>{};
    // Detect inverted maps (rohd->prim) where keys are ROHD names.
    final anyKeyIsRohd = prim.portMap.keys.any(rohdPortNames.contains);
    final anyKeyIsPrim = prim.portMap.keys.any(primPortNames.contains);
    if (anyKeyIsRohd && !anyKeyIsPrim) {
      // Invert rohd->prim into prim->rohd lists
      for (final e in prim.portMap.entries) {
        primToRohdLists[e.value] = [e.key];
      }
    } else {
      for (final e in prim.portMap.entries) {
        final primPort = e.key;
        final mapping = e.value;
        if (mapping.startsWith('re:')) {
          final pattern = RegExp(mapping.substring(3));
          // Collect all ROHD ports matching the regex and sort
          // deterministically
          final matches = rohdPortNames.where(pattern.hasMatch).toList()
            ..sort();
          if (matches.isNotEmpty) {
            primToRohdLists[primPort] = matches;
          }
        } else {
          // Literal mapping or placeholder (like 'A'/'B'). Store the literal
          // string so calling code can detect placeholders vs literal names.
          primToRohdLists[primPort] = [mapping];
        }
      }
    }

    // Helper to map for a given direction. Treat prim ports missing from
    // `portDirs` as inputs by default so registrations can declare only
    // outputs/inouts when convenient.
    Map<String, String> doDirection(String direction, List<String> rohdPorts) {
      String getDir(String p) => portDirs[p] ?? 'input';
      // Primitive ports of this direction, sorted
      final primPorts =
          primPortNames.where((p) => getDir(p) == direction).toList()..sort();

      final mapping = <String, String>{}; // rohd -> prim

      // 1) Literal mappings from portMap. For regex mappings we collected
      // candidate lists; pick the first unassigned ROHD match for each
      // prim-port and mark it assigned so matches are not reused.
      final assignedPrim = <String>{};
      final assignedRohd = <String>{};
      for (final primPort in primPorts) {
        final candidates = primToRohdLists[primPort];
        if (candidates != null && candidates.isNotEmpty) {
          // If any candidate is an actual ROHD port name, assign the first
          // one that is not already assigned.
          String? chosen;
          for (final cand in candidates) {
            if (rohdPorts.contains(cand) && !assignedRohd.contains(cand)) {
              chosen = cand;
              break;
            }
          }
          if (chosen != null) {
            mapping[chosen] = primPort;
            assignedPrim.add(primPort);
            assignedRohd.add(chosen);
            continue;
          }
          // If candidates exist but none are actual ROHD names, fall
          // through to placeholder handling below (mapping may be a
          // placeholder like 'A' or 'B').
        }
        // Also support the legacy case where primToRohdLists may be empty
        // and prim.portMap contains a literal ROHD name.
        final mappedLiteral = prim.portMap[primPort];
        if (mappedLiteral != null && rohdPorts.contains(mappedLiteral)) {
          mapping[mappedLiteral] = primPort;
          assignedPrim.add(primPort);
          assignedRohd.add(mappedLiteral);
          continue;
        }
      }

      // 2) Placeholder groups (e.g., 'A', 'B')
      // Group prim ports by their placeholder value
      final placeholderGroups = <String, List<String>>{};
      for (final primPort in primPorts) {
        if (assignedPrim.contains(primPort)) {
          continue;
        }
        final mapped = prim.portMap[primPort];
        if (mapped != null && RegExp(r'^[A-Z][0-9]*$').hasMatch(mapped)) {
          final key = mapped.replaceAll(RegExp('[0-9]+'), '');
          placeholderGroups.putIfAbsent(key, () => []).add(primPort);
          assignedPrim.add(primPort);
        }
      }
      // Sort each group's prim ports for deterministic assignment
      for (final g in placeholderGroups.values) {
        g.sort();
      }

      // Assign ROHD ports to placeholder prim ports in sorted order
      var rohdIdx = 0;
      for (final primList in placeholderGroups.values) {
        for (final primPort in primList) {
          while (rohdIdx < rohdPorts.length &&
              assignedRohd.contains(rohdPorts[rohdIdx])) {
            rohdIdx++;
          }
          if (rohdIdx >= rohdPorts.length) {
            break;
          }
          final rohdName = rohdPorts[rohdIdx++];
          mapping[rohdName] = primPort;
          assignedRohd.add(rohdName);
        }
      }

      // 3) Positional mapping for any remaining prim ports
      // Collect remaining prim ports not assigned
      final remainingPrim =
          primPorts.where((p) => !mapping.values.contains(p)).toList()..sort();
      // Collect remaining rohd ports
      final remainingRohd =
          rohdPorts.where((r) => !assignedRohd.contains(r)).toList()..sort();

      // No primitive-specific positional heuristics; rely on descriptor
      // mappings and deterministic regex consumption above.

      for (var i = 0;
          i < remainingPrim.length && i < remainingRohd.length;
          i++) {
        mapping[remainingRohd[i]] = remainingPrim[i];
      }

      return mapping;
    }

    final result = <String, String>{}
      ..addAll(doDirection('input', rohdInputs))
      ..addAll(doDirection('output', rohdOutputs))
      ..addAll(doDirection('inout', rohdInouts));
    // If the descriptor did not supply explicit `portDirs`, infer primitive
    // port directions from the instantiation point (ROHD ports) so the
    // caller can use instance-derived directions rather than requiring the
    // descriptor to provide them. This mirrors how combinational/raw-port
    // instances display correctly using their instantiation context.
    if (prim.portDirs.isEmpty) {
      // Build reverse map: primPort -> list of rohd ports mapped to it
      final primToRohd = <String, List<String>>{};
      for (final e in result.entries) {
        primToRohd.putIfAbsent(e.value, () => []).add(e.key);
      }

      String decideForPrim(String primPort) {
        final rohdList = primToRohd[primPort] ?? const <String>[];
        return rohdList.any((r) => childModule.ports[r]?.isInOut ?? false)
            ? 'inout'
            : (rohdList.any((r) => childModule.ports[r]?.isOutput ?? false)
                ? 'output'
                : 'input');
      }

      // Populate missing entries in the provided portDirs map.
      for (final primPort in primPortNames) {
        portDirs.putIfAbsent(
            primPort,
            () => primPort == 'Y'
                ? (childModule.outputs.isNotEmpty ? 'output' : 'input')
                : decideForPrim(primPort));
      }
    }

    return result;
  }

  /// Build a primitive connection map (`primPort` -> bit-id list) using the
  /// deterministic ROHD->primitive port mapping and the provided
  /// `idsForRohd` lookup function which returns the bit ids for a ROHD
  /// port name. This function also calls the safe finalizer to allow
  /// parameter inference that depends on concrete connections.
  static Map<String, List<Object?>> buildPrimitiveConnections(
      Module childModule,
      PrimitiveDescriptor prim,
      Map<String, Object?> parameters,
      Map<String, String> portDirs,
      List<Object?> Function(String rohdName) idsForRohd) {
    final connMap = <String, List<Object?>>{};
    final rohdToPrim = mapRohdToPrimitivePorts(prim, childModule, portDirs);

    for (final entry in rohdToPrim.entries) {
      final rohdName = entry.key;
      final primPortName = entry.value;
      final ids = idsForRohd(rohdName);
      if (ids.isNotEmpty) {
        connMap[primPortName] = ids;
      }
    }

    // Allow primitive logic to finalize parameters using the concrete
    // connection ids we built.
    finalizePrimitiveCell(childModule, prim, parameters, connMap);

    return connMap;
  }

  /// Convenience wrapper used by the dumper when the lookup for ROHD port
  /// ids needs to resolve ports via either a previously-produced
  /// `SynthesisResult` for the child (preferred) or a child `ModuleMap`
  /// (fallback). The [idsForChildLogic] callback should accept a `Logic`
  /// and return the corresponding bit id list. The [childResultLookup]
  /// callback, when provided, should return the `SynthesisResult` for a
  /// given child module or null if not present. This allows using cached
  /// synthesis outputs rather than rebuilding ModuleMaps.
  static Map<String, List<Object?>>
      buildPrimitiveConnectionsWithChildLogicLookup(
          Module childModule,
          PrimitiveDescriptor prim,
          Map<String, Object?> parameters,
          Map<String, String> portDirs,
          SynthesisResult? Function(Module) childResultLookup,
          List<Object?> Function(Logic) idsForChildLogic) {
    // Adapter: convert rohdName -> idsForRohd by resolving the Logic
    // either from the SchematicSynthesisResult (if available), the
    // child ModuleMap contained within that result, or directly from
    // the child module as a last resort.
    List<Object?> idsForRohd(String rohdName) {
      final res = childResultLookup(childModule);
      // If we have a SchematicSynthesisResult, try to use its port map.
      if (res is SchematicSynthesisResult) {
        final ports = res.ports;
        if (ports.containsKey(rohdName)) {
          // ports[rohdName]['bits'] is a List<Object?> of bit ids
          final bits = (ports[rohdName]! as Map)['bits'];
          if (bits is List) {
            return bits.cast<Object?>();
          }
        }
      }

      // Fallback: try to obtain the logic from the child's ModuleMap if
      // the result provides a way (many SchematicSynthesisResults do not
      // expose ModuleMap directly), otherwise use the module's port
      // reference and resolve via idsForChildLogic.
      final logic = childModule.ports[rohdName];
      if (logic == null) {
        return <Object?>[];
      }
      return idsForChildLogic(logic);
    }

    return buildPrimitiveConnections(
        childModule, prim, parameters, portDirs, idsForRohd);
  }
}

/// Represents a primitive cell in the schematic JSON output.
///
/// Used by [Schematic.schematicCell] to return custom cell representations.
class SchematicCellDefinition {
  /// The Yosys-style type name (e.g., `$and`, `$mux`, `$dff`).
  final String type;

  /// Parameters for the cell (e.g., `{'WIDTH': 8}`).
  final Map<String, Object?> parameters;

  /// Attributes for the cell.
  final Map<String, Object?> attributes;

  /// Port directions: port name → `'input'` | `'output'` | `'inout'`.
  final Map<String, String> portDirections;

  /// Creates a [SchematicCellDefinition].
  const SchematicCellDefinition({
    required this.type,
    this.parameters = const {},
    this.attributes = const {},
    this.portDirections = const {},
  });
}

/// What kind of schematic definition this [Module] generates, or whether it
/// does at all.
enum SchematicDefinitionGenerationType {
  /// No definition will be generated; the module is a primitive/leaf.
  none,

  /// A standard definition will be generated via the normal synthesis flow.
  standard,

  /// A custom definition will be generated via [Schematic.schematicDefinition].
  custom,
}

/// Allows a [Module] to control the instantiation and/or definition of
/// generated schematic JSON for that module.
///
/// Similar to [SystemVerilog] mixin for SystemVerilog synthesis, this mixin
/// provides hooks for modules to customize their schematic representation.
///
/// ## Architecture
///
/// For simple primitives, prefer using [PrimitiveSchematic] mixin which handles
/// most common cases automatically. Use this mixin directly for:
/// - Complex primitives requiring custom cell emission (see
///   [emitSchematicCells])
/// - Modules needing descriptor-based primitives (see [primitiveDescriptor])
/// - Modules requiring custom definition generation
///
/// Core ROHD modules (And2Gate, Or2Gate, etc.) are registered in
/// [CoreGatePrimitives] by type and do not need mixins added.
///
/// ## Example: Descriptor-based primitive
///
/// ```dart
/// class MyPrimitive extends Module with Schematic {
///   MyPrimitive(Logic a, Logic b) {
///     a = addInput('a', a);
///     b = addInput('b', b);
///     addOutput('y') <= a & b;
///   }
///
///   @override
///   PrimitiveDescriptor primitiveDescriptor() => const PrimitiveDescriptor(
///     primitiveName: r'$and',
///     portMap: {'a': 'A', 'b': 'B', 'y': 'Y'},
///     portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
///   );
/// }
/// ```
///
/// For even simpler cases, use [PrimitiveSchematic] mixin instead.
mixin Schematic on Module {
  /// Generates a custom schematic cell definition to be used when this module
  /// is instantiated as a child in another module's schematic.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively, of the module that would have been instantiated.
  /// [ports] provides access to the actual port [Logic] objects.
  ///
  /// Return a [SchematicCellDefinition] to provide custom cell data.
  /// Return `null` to use standard cell generation.
  ///
  /// By default, returns `null` (use standard generation).
  SchematicCellDefinition? schematicCell(
    String instanceType,
    String instanceName,
    Map<String, Logic> ports,
  ) =>
      null;

  /// A custom schematic module definition to be produced for this [Module].
  ///
  /// Returns a map representing the module's JSON structure with keys:
  /// - `'ports'`: `Map<String, Map<String, Object?>>`
  /// - `'cells'`: `Map<String, Map<String, Object?>>`
  /// - `'netnames'`: `Map<String, Object?>`
  /// - `'attributes'`: `Map<String, Object?>`
  ///
  /// If `null` is returned, a standard definition will be generated.
  /// If an empty map is returned, no definition will be generated.
  ///
  /// This function should have no side effects and always return the same thing
  /// for the same inputs.
  ///
  /// By default, returns `null` (use standard generation).
  Map<String, Object?>? schematicDefinition(String definitionType) => null;

  /// What kind of schematic definition this [Module] generates, or whether it
  /// does at all.
  ///
  /// By default, this is automatically calculated based on the return value of
  /// [schematicDefinition] and [schematicCell].
  SchematicDefinitionGenerationType get schematicDefinitionType {
    // If schematicCell returns non-null, treat as primitive (no definition)
    // We use an empty ports map for the check since we just need to see if
    // the module provides a custom implementation.
    final cell = schematicCell('*PLACEHOLDER*', '*PLACEHOLDER*', {});
    if (cell != null) {
      return SchematicDefinitionGenerationType.none;
    }

    // Check schematicDefinition
    final def = schematicDefinition('*PLACEHOLDER*');
    if (def == null) {
      return SchematicDefinitionGenerationType.standard;
    } else if (def.isNotEmpty) {
      return SchematicDefinitionGenerationType.custom;
    } else {
      return SchematicDefinitionGenerationType.none;
    }
  }

  /// Whether this module should be treated as a primitive in schematic output.
  ///
  /// When `true`, no separate module definition is generated; instead, the
  /// module is represented directly as a cell in the parent module.
  ///
  /// Override this to `true` for leaf primitives that should not have their
  /// own definition.
  ///
  /// By default, returns `true` if [schematicDefinitionType] is
  /// [SchematicDefinitionGenerationType.none].
  bool get isSchematicPrimitive =>
      schematicDefinitionType == SchematicDefinitionGenerationType.none;

  /// The Yosys primitive type name to use when this module is emitted as a
  /// cell (e.g., `$and`, `$mux`, `$dff`).
  ///
  /// Only used when [isSchematicPrimitive] is `true` or [schematicCell]
  /// returns `null` but the synthesizer determines this is a primitive.
  ///
  /// By default, returns `null`, which defers to the descriptor or type
  /// registry for the primitive name.
  String? get schematicPrimitiveName => null;

  /// Optional: provide a [PrimitiveDescriptor] describing how this module
  /// should be emitted as a primitive cell. If non-null, this descriptor
  /// will be used instead of [CoreGatePrimitives] type-based lookup.
  ///
  /// Default: `null` (no module-specific descriptor).
  @internal
  PrimitiveDescriptor? primitiveDescriptor() => null;

  /// Optional hook for modules to directly emit one or more schematic cells
  /// for their instantiation. This allows a module to control complex
  /// expansions (for example, `Sequential` expanding to mux + dff cells)
  /// without requiring external handlers.
  ///
  /// Returning `true` indicates the module emitted the necessary cells and
  /// the caller should `continue` (no further primitive handling). The
  /// default implementation returns `false`.
  @internal
  bool emitSchematicCells({
    required Map<String, Logic> ports,
    required Map<Logic, List<Object?>> internalNetIds,
    required List<Object?> Function(Logic) idsForChildLogic,
    required Map<String, Map<String, Object?>> cells,
    required Map<String, List<Object?>> syntheticNets,
    required int Function() nextInternalNetIdGetter,
    required void Function(int) nextInternalNetIdSetter,
  }) =>
      false;

  /// Optional: allow a module to build the final primitive cell map for a
  /// given [PrimitiveDescriptor]. If non-null is returned, it will be used
  /// directly as the cell JSON (with keys `type`, `parameters`,
  /// `port_directions`, `connections`, etc.). Return `null` to defer to
  /// [PrimitiveHelper] for standard cell generation.
  @internal
  Map<String, Object?>? schematicPrimitiveCell(
    PrimitiveDescriptor prim,
    List<Object?> Function(Logic) idsForChildLogic, {
    required Map<Logic, List<Object?>> internalNetIds,
    required Map<String, List<Object?>> syntheticNets,
    required int Function() nextInternalNetIdGetter,
    required void Function(int) nextInternalNetIdSetter,
    bool filterConstInputsToCombinational = false,
    SynthesisResult? Function(Module)? lookupExistingResult,
  }) =>
      null;

  /// Helper to determine whether a [Module] should be considered a
  /// schematic primitive for purposes of emission and validation.
  ///
  /// This centralizes primitive detection logic. Checks module-provided
  /// hooks first (e.g., `primitiveDescriptor()`, `isSchematicPrimitive`),
  /// then consults [CoreGatePrimitives] for type-based registration.
  static bool isPrimitiveModule(Module m) {
    if (m is Schematic) {
      if (m.primitiveDescriptor() != null ||
          m.isSchematicPrimitive ||
          m.schematicPrimitiveName != null ||
          m.schematicDefinitionType == SchematicDefinitionGenerationType.none) {
        return true;
      }
    }

    // Check core gate registry
    if (CoreGatePrimitives.instance.lookupByType(m) != null) {
      return true;
    }

    // All core ROHD modules are in CoreGatePrimitives; no fallback needed
    return false;
  }

  /// Indicates that this module is only wires, no logic inside, which can be
  /// leveraged for pruning in schematic generation.
  @internal
  bool get isSchematicWiresOnly => false;
}

/// Allows a [Module] to define a type of [Schematic] which can be represented
/// as an inline primitive cell without generating a separate definition.
///
/// This is the schematic equivalent of [InlineSystemVerilog].
///
/// Use this mixin when you have a simple module that should always be
/// represented as a specific primitive type with fixed parameters.
///
/// ## Example
///
/// ```dart
/// class MySimpleAnd extends Module with InlineSchematic {
///   MySimpleAnd(Logic a, Logic b) {
///     a = addInput('a', a);
///     b = addInput('b', b);
///     addOutput('y') <= a & b;
///   }
///
///   @override
///   String get schematicPrimitiveName => r'$and';
///
///   @override
///   Map<String, String> get schematicPortMap => {
///     'a': 'A',
///     'b': 'B',
///     'y': 'Y',
///   };
/// }
/// ```
mixin InlineSchematic on Module implements Schematic {
  /// The Yosys primitive type to use for this inline cell.
  ///
  /// Override this to specify the primitive type (e.g., `$and`, `$or`).
  @override
  String get schematicPrimitiveName;

  /// Parameters to include in the primitive cell.
  ///
  /// Override to provide cell parameters like `{'WIDTH': 8}`.
  Map<String, Object?> get schematicParameters => const {};

  /// Port name mapping from ROHD port names to primitive port names.
  ///
  /// Override if the primitive uses different port names than the ROHD module.
  /// For example: `{'a': 'A', 'b': 'B', 'y': 'Y'}`.
  Map<String, String> get schematicPortMap => const {};

  @override
  bool get isSchematicPrimitive => true;

  @override
  SchematicCellDefinition? schematicCell(
    String instanceType,
    String instanceName,
    Map<String, Logic> ports,
  ) {
    final portDirs = <String, String>{};
    for (final entry in ports.entries) {
      final primPortName = schematicPortMap[entry.key] ?? entry.key;
      final logic = entry.value;
      portDirs[primPortName] = logic.isInput
          ? 'input'
          : logic.isOutput
              ? 'output'
              : 'inout';
    }

    return SchematicCellDefinition(
      type: schematicPrimitiveName,
      parameters: schematicParameters,
      portDirections: portDirs,
    );
  }

  @override
  SchematicDefinitionGenerationType get schematicDefinitionType =>
      SchematicDefinitionGenerationType.none;

  @override
  Map<String, Object?>? schematicDefinition(String definitionType) => {};

  @internal
  @override
  bool get isSchematicWiresOnly => false;
}

/// A mixin for modules that can be represented as Yosys primitive cells using
/// a [PrimitiveDescriptor].
///
/// This mixin provides a default implementation of [schematicPrimitiveCell]
/// that builds the primitive cell JSON from the descriptor and module ports.
///
/// Modules using this mixin should override [primitiveDescriptor] to provide
/// their descriptor. The mixin handles port mapping, parameter inference, and
/// connection building automatically.
///
/// ## Example
///
/// ```dart
/// class And2Gate extends Module with PrimitiveSchematic {
///   And2Gate(Logic a, Logic b) {
///     a = addInput('a', a, width: a.width);
///     b = addInput('b', b, width: b.width);
///     addOutput('y', width: a.width);
///   }
///
///   @override
///   PrimitiveDescriptor primitiveDescriptor() => const PrimitiveDescriptor(
///     primitiveName: r'$and',
///     portMap: {'a': 'A', 'b': 'B', 'y': 'Y'},
///     portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
///   );
/// }
/// ```
mixin PrimitiveSchematic on Module implements Schematic {
  @override
  bool get isSchematicPrimitive => true;

  @override
  SchematicDefinitionGenerationType get schematicDefinitionType =>
      SchematicDefinitionGenerationType.none;

  @override
  Map<String, Object?>? schematicDefinition(String definitionType) => {};

  @override
  @internal
  Map<String, Object?>? schematicPrimitiveCell(
    PrimitiveDescriptor prim,
    List<Object?> Function(Logic) idsForChildLogic, {
    required Map<Logic, List<Object?>> internalNetIds,
    required Map<String, List<Object?>> syntheticNets,
    required int Function() nextInternalNetIdGetter,
    required void Function(int) nextInternalNetIdSetter,
    bool filterConstInputsToCombinational = false,
    SynthesisResult? Function(Module)? lookupExistingResult,
  }) {
    // Build primitive cell using the descriptor.
    // This is a simplified version that handles common cases.
    // Modules can override this for custom behavior.

    final cellType = prim.primitiveName;
    final parameters = <String, Object?>{...prim.defaultParams};
    final portDirs = <String, String>{...prim.portDirs};
    final connections = <String, List<Object?>>{};

    // Access module's ports - 'this' is the Module since mixin is 'on Module'
    final modulePorts = (this as Module).ports;

    // Build ROHD->primitive port mapping
    final rohdToPrim = <String, String>{};
    if (prim.useRawPortNames) {
      // Use module's actual port names
      for (final name in modulePorts.keys) {
        rohdToPrim[name] = name;
      }
    } else {
      // Use descriptor's portMap
      for (final entry in prim.portMap.entries) {
        final primPort = entry.key;
        final rohdName = entry.value;
        if (rohdName.startsWith('re:')) {
          // Regex mapping - find matching ROHD port
          final pattern = RegExp(rohdName.substring(3));
          final matches = modulePorts.keys.where(pattern.hasMatch).toList()
            ..sort();
          if (matches.isNotEmpty) {
            rohdToPrim[matches.first] = primPort;
          }
        } else if (modulePorts.containsKey(rohdName)) {
          // Direct mapping
          rohdToPrim[rohdName] = primPort;
        }
      }

      // Fill in unmapped ports with simple heuristics
      final unmappedRohd = modulePorts.keys.toSet()..removeAll(rohdToPrim.keys);
      final unmappedPrim = portDirs.keys.toSet()..removeAll(rohdToPrim.values);

      // Simple positional mapping for remaining ports
      final unmappedRohdList = unmappedRohd.toList()..sort();
      final unmappedPrimList = unmappedPrim.toList()..sort();
      for (var i = 0;
          i < unmappedRohdList.length && i < unmappedPrimList.length;
          i++) {
        rohdToPrim[unmappedRohdList[i]] = unmappedPrimList[i];
      }
    }

    // Build connections using the mapping
    for (final entry in rohdToPrim.entries) {
      final rohdName = entry.key;
      final primPort = entry.value;
      final logic = modulePorts[rohdName];
      if (logic != null) {
        final ids = idsForChildLogic(logic);
        if (ids.isNotEmpty) {
          connections[primPort] = ids;
        }
      }
    }

    // Infer parameters from port widths if specified in descriptor
    for (final entry in prim.paramFromPort.entries) {
      final paramName = entry.key;
      final primPort = entry.value;
      if (paramName.endsWith('_WIDTH') && connections.containsKey(primPort)) {
        parameters[paramName] = connections[primPort]!.length;
      }
    }

    // Ensure minimum parameter values
    void ensureIntParam(String k, int defaultVal) {
      final v = parameters[k];
      if (v is int) {
        if (v <= 0) {
          parameters[k] = defaultVal;
        }
      } else {
        parameters[k] = defaultVal;
      }
    }

    ensureIntParam('A_WIDTH', 1);
    ensureIntParam('B_WIDTH', 1);
    ensureIntParam('Y_WIDTH', 1);

    // Infer port directions if not provided
    if (prim.portDirs.isEmpty) {
      for (final entry in rohdToPrim.entries) {
        final rohdName = entry.key;
        final primPort = entry.value;
        final logic = modulePorts[rohdName];
        if (logic != null && !portDirs.containsKey(primPort)) {
          portDirs[primPort] = logic.isInput
              ? 'input'
              : logic.isOutput
                  ? 'output'
                  : 'inout';
        }
      }
    }

    return {
      'hide_name': 0,
      'type': cellType,
      'parameters': parameters,
      'attributes': <String, Object?>{},
      'port_directions': portDirs,
      'connections': connections,
    };
  }

  @internal
  @override
  bool get isSchematicWiresOnly => false;
}
