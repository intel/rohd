// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_primitives.dart
// Primitive mapping helpers extracted from schematic_dumper for reuse.

// 2025 December 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/module_map.dart';
import 'package:rohd/src/synthesizers/schematic/module_utils.dart';

/// Descriptor describing how a ROHD helper module maps to a Yosys
/// primitive type.
class PrimitiveDescriptor {
  /// The Yosys primitive type name (e.g. "\$concat", "\$dff", "\$mux").
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

/// Singleton registry for primitive mappings used by the schematic dumper.
class Primitives {
  Primitives._() {
    _populateDefaults();
  }

  /// The singleton instance.
  static final Primitives instance = Primitives._();

  final Map<String, PrimitiveDescriptor> _byDefinitionName = {};

  /// Registers a [PrimitiveDescriptor] for a given ROHD module.
  void register(String definitionName, PrimitiveDescriptor desc) {
    _byDefinitionName[definitionName] = desc;
  }

  /// Find a registered [PrimitiveDescriptor] by ROHD module definition name.
  PrimitiveDescriptor? lookupByDefinitionName(String defName) =>
      _byDefinitionName[defName];

  /// Lookup a [PrimitiveDescriptor] for a given [Module] by trying exact
  /// definition name match first, then case-insensitive match, then
  /// pattern match.
  PrimitiveDescriptor? lookupForModule(Module m) {
    final def = m.definitionName;
    final nm = m.name;

    final p = lookupByDefinitionName(def);
    if (p != null) {
      return p;
    }

    final defLower = def.toLowerCase();
    final nmLower = nm.toLowerCase();
    for (final entry in _byDefinitionName.entries) {
      final keyLower = entry.key.toLowerCase();
      if (keyLower == defLower || keyLower == nmLower) {
        return entry.value;
      }
    }

    for (final entry in _byDefinitionName.entries) {
      final key = entry.key;
      final pattern = RegExp(
          '(^|[^A-Za-z0-9])${RegExp.escape(key)}(\$|[^A-Za-z0-9])',
          caseSensitive: false);
      if (pattern.hasMatch(def) || pattern.hasMatch(nm)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Compute the primitive cell representation for a `Module` that maps to
  /// a known primitive descriptor. Returns a map containing keys:
  /// - 'type' -> String primitive type (e.g. r'$concat')
  /// - 'parameters' -> `Map<String,Object?> `of parameter values
  /// - 'port_directions' -> `Map<String,String>` mapping primitive port names
  ///    to directions expected by the loader ('input'/'output'/'inout')
  Map<String, Object?> computePrimitiveCell(
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
  void finalizePrimitiveCell(Module childModule, PrimitiveDescriptor prim,
      Map<String, Object?> parameters, Map<String, List<Object?>> connMap) {
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
  Map<String, String> mapRohdToPrimitivePorts(PrimitiveDescriptor prim,
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
  Map<String, List<Object?>> buildPrimitiveConnections(
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
  /// ids needs to resolve ports via a child ModuleMap (or fallback to the
  /// child module's own ports). The [idsForChildLogic] callback should
  /// accept a `Logic` and return the corresponding bit id list. The
  /// [childMapLookup] callback, when provided, should return the ModuleMap
  /// for a given child module or null if not present.
  Map<String, List<Object?>> buildPrimitiveConnectionsWithChildLogicLookup(
      Module childModule,
      PrimitiveDescriptor prim,
      Map<String, Object?> parameters,
      Map<String, String> portDirs,
      ModuleMap? Function(Module) childMapLookup,
      List<Object?> Function(Logic) idsForChildLogic) {
    // Adapter: convert rohdName -> idsForRohd by resolving the Logic
    // either from the child ModuleMap (if available) or directly from
    // the child module.
    List<Object?> idsForRohd(String rohdName) {
      final childMap = childMapLookup(childModule);
      final logic =
          childMap?.module.ports[rohdName] ?? childModule.ports[rohdName];
      if (logic == null) {
        return <Object?>[];
      }
      return idsForChildLogic(logic);
    }

    return buildPrimitiveConnections(
        childModule, prim, parameters, portDirs, idsForRohd);
  }

  void _populateDefaults() {
    register(
        'Swizzle',
        const PrimitiveDescriptor(
          primitiveName: r'$concat',
          // ROHD swizzles commonly name inputs like `in0_<name>`,
          // `in1_<name>` and the output `swizzled` or `out`. Use regex
          // mappings so the dumper can deterministically pick inputs and
          // output without relying on positional heuristics.
          portMap: {
            'A': r're:^in\d+_.+',
            'B': r're:^in\d+_.+',
            'Y': r're:^(?:swizzled$|out$)'
          },
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'BusSubset',
        const PrimitiveDescriptor(
          primitiveName: r'$slice',
          // BusSubset (slice) instances often expose outputs with names
          // containing `_subset_HIGH_LOW`. Inputs are typically `in...` or
          // `A`. Prefer regex matches for both A (source bus) and Y
          // (sliced output) so parameters can be extracted from names.
          portMap: {
            'A': r're:^in\d*_.+|^in_.+|^A$',
            'Y': r're:.*_subset_\d+_\d+|^out$'
          },
          paramFromPort: {'HIGH': 'A', 'LOW': 'A'},
          portDirs: {'A': 'input', 'Y': 'output'},
        ));

    // Comparison gates: ROHD uses in0_<name>, in1_<name> for inputs.
    register(
        'Equals',
        const PrimitiveDescriptor(
          primitiveName: r'$eq',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'NotEquals',
        const PrimitiveDescriptor(
          primitiveName: r'$ne',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'LessThan',
        const PrimitiveDescriptor(
          primitiveName: r'$lt',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'LessThanOrEqual',
        const PrimitiveDescriptor(
          primitiveName: r'$le',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'GreaterThan',
        const PrimitiveDescriptor(
          primitiveName: r'$gt',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        'GreaterThanOrEqual',
        const PrimitiveDescriptor(
          primitiveName: r'$ge',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    register(
        'lshift',
        const PrimitiveDescriptor(
            primitiveName: r'$shl',
            portMap: {'A': 're:^in_.+', 'B': 're:^shiftAmount_.+'},
            paramFromPort: {'A_WIDTH': 'A'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'rshift',
        const PrimitiveDescriptor(
            primitiveName: r'$shr',
            portMap: {'A': 're:^in_.+', 'B': 're:^shiftAmount_.+'},
            paramFromPort: {'A_WIDTH': 'A'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'ARShift',
        const PrimitiveDescriptor(
          primitiveName: r'$shiftx',
          portMap: {'A': 'A', 'B': 'B', 'Y': 'Y'},
          paramFromPort: {'A_WIDTH': 'A'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    register(
        'And2Gate',
        const PrimitiveDescriptor(
            primitiveName: r'$and',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'Or2Gate',
        const PrimitiveDescriptor(
            primitiveName: r'$or',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'Xor2Gate',
        const PrimitiveDescriptor(
            primitiveName: r'$xor',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'NotGate',
        const PrimitiveDescriptor(
            primitiveName: r'$not',
            portMap: {'A': 're:^in_.+'},
            portDirs: {'A': 'input', 'Y': 'output'}));

    register(
        'AndUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$logic_and',
            portDirs: {'A': 'input', 'Y': 'output'}));
    register(
        'OrUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$logic_or',
            portDirs: {'A': 'input', 'Y': 'output'}));
    register(
        'XorUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$xor', portDirs: {'A': 'input', 'Y': 'output'}));

    // Note: bitwise/logical gate descriptors are updated below with
    // explicit `portDirs`; the earlier implicit registrations were
    // redundant and have been removed to avoid confusion.

    // Update bitwise/logical gate descriptors to include directions.
    register(
        'BitwiseAnd',
        const PrimitiveDescriptor(
            primitiveName: r'$and',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'BitwiseOr',
        const PrimitiveDescriptor(
            primitiveName: r'$or',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'BitwiseXor',
        const PrimitiveDescriptor(
            primitiveName: r'$xor',
            portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'LogicNot',
        const PrimitiveDescriptor(
            primitiveName: r'$not',
            portMap: {'A': 're:^in_.+'},
            portDirs: {'A': 'input', 'Y': 'output'}));

    register(
        'mux',
        const PrimitiveDescriptor(
            primitiveName: r'$mux',
            // Use regex-based mappings to detect ROHD dynamic port names like
            // control_<name>, d0_<name>, d1_<name>, and out. Values prefixed
            // with 're:' are treated as regular expressions against ROHD port
            // names.
            portMap: {
              // Match common selector names: control_<name>, sel_<name>,
              // s_<name>, in0_/in1_ (sometimes select is named as in0/in1), or
              // literal 'A'.
              'S':
                  r're:^(?:_?control_.+|_?sel_.+|_?s_.+|in0_.+|in1_.+|A$|.*_subset_\d+_\d+)',
              // Data inputs: match d1_/d0_, or literal B/C/A depending on ROHD
              'A': r're:^(?:d1_.+|B$|d1$|d1_.+)',
              'B': r're:^(?:d0_.+|C$|d0$|d0_.+)',
              'Y': r're:^(?:out$|Y$)'
            },
            // The WIDTH parameter should come from the data input (d1/d0), but
            // we leave this as 'B' for compatibility — callers interpret this
            // as the ROHD port name after mapping resolution.
            paramFromPort: {
              'WIDTH': 'B'
            }));
    // Merged mux descriptor: provide port mappings, parameter source,
    // and explicit port directions so fallback inference isn't required.
    register(
        'mux',
        const PrimitiveDescriptor(primitiveName: r'$mux', portMap: {
          'S':
              r're:^(?:_?control_.+|_?sel_.+|_?s_.+|in0_.+|in1_.+|A$|.*_subset_\d+_\d+)',
          'A': r're:^(?:d1_.+|B$|d1$|d1_.+)',
          'B': r're:^(?:d0_.+|C$|d0$|d0_.+)',
          'Y': r're:^(?:out$|Y$)'
        }, paramFromPort: {
          'WIDTH': 'B'
        }, portDirs: {
          'S': 'input',
          'A': 'input',
          'B': 'input',
          'Y': 'output'
        }));

    register(
        'mul',
        const PrimitiveDescriptor(
            primitiveName: r'$mul',
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));

    register(
        'AddSigned',
        const PrimitiveDescriptor(
            primitiveName: r'$add',
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'SubSigned',
        const PrimitiveDescriptor(
            primitiveName: r'$sub',
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'AddUnsigned',
        const PrimitiveDescriptor(
            primitiveName: r'$add',
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));
    register(
        'SubUnsigned',
        const PrimitiveDescriptor(
            primitiveName: r'$sub',
            portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'}));

    register(
        'FlipFlop',
        const PrimitiveDescriptor(primitiveName: r'$dff', portMap: {
          'd': 'D',
          'q': 'Q',
          'clk': 'CLK',
          'en': 'EN',
          'reset': 'SRST'
        }, portDirs: {
          'd': 'input',
          'q': 'output',
          'clk': 'input',
          'en': 'input',
          'reset': 'input'
        }));

    // Sequential is handled specially by SequentialHandler:
    // - Simple Sequential (1 data input/output) → $dff primitive
    // - Complex Sequential.multi → generates internal mux + dff structure
    //   Register it so that generatesDefinition() returns false (it's a leaf).
    //   The actual cell emission is done by SequentialHandler, not this
    //   descriptor.
    register(
        'Sequential',
        const PrimitiveDescriptor(
            primitiveName: r'$sequential', useRawPortNames: true));

    // Add and Combinational have dynamic port names per instance
    register(
        'Add',
        const PrimitiveDescriptor(
            primitiveName: r'$add', useRawPortNames: true));
    register(
        'Combinational',
        const PrimitiveDescriptor(
            primitiveName: r'$combinational', useRawPortNames: true));

    register(
        'AndUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$logic_and',
            portDirs: {'A': 'input', 'Y': 'output'}));
    register(
        'OrUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$logic_or',
            portDirs: {'A': 'input', 'Y': 'output'}));
    register(
        'XorUnary',
        const PrimitiveDescriptor(
            primitiveName: r'$xor', portDirs: {'A': 'input', 'Y': 'output'}));
  }
}
