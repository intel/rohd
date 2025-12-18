// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// constant_handler.dart
// Encapsulates constant collection and emission logic used by the schematic
// dumper. This file contains `PerInputConstInfo`, `ConstantCollectionResult`,
// and `ConstantHandler`.
//
// 2025 December 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

import 'package:rohd/src/synthesizers/schematic/module_map.dart';
import 'package:rohd/src/synthesizers/schematic/schematic_primitives.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Information about a per-input constant driver.
class PerInputConstInfo {
  /// The list of internal net IDs driving the input.
  final List<int> _ids;

  /// The constant value being driven.
  final BigInt _value;

  /// Creates a [PerInputConstInfo].
  PerInputConstInfo({
    required List<int> ids,
    required BigInt value,
  })  : _value = value,
        _ids = ids;

  /// The bit-width of the constant driver.
  int get width => _ids.length;

  /// The stable net name for this constant driver.
  /// Use a simple name `const_<value>` as the base; replication suffixes
  /// will be appended by the emitter if necessary to avoid collisions.
  String get netName => 'const_$_value';
}

/// Result of constant collection.
class ConstantCollectionResult {
  final Map<String, List<int>> _patternToIds;
  final Map<Logic, PerInputConstInfo> _perInputConsts;

  /// The set of IDs that should not have shared $const cells emitted for them.
  final Set<int> blockedIds;

  /// Creates a [ConstantCollectionResult].
  ConstantCollectionResult({
    required Map<String, List<int>> patternToIds,
    required Map<Logic, PerInputConstInfo> perInputConsts,
    required this.blockedIds,
  })  : _perInputConsts = perInputConsts,
        _patternToIds = patternToIds;

  /// Generates a stable name for a constant pattern given its [pattern]
  /// string and associated [ids].
  static String nameForPattern(String pattern, List<int> ids) =>
      'const_${ids.length}_${pattern.hashCode}';
}

/// Handler for collecting and emitting constants in a module tree.
class ConstantHandler {
  /// Collect constants from a module and its children.
  ///
  /// Returns a [ConstantCollectionResult] containing all constant state,
  /// and populates [internalNetIds] with ID mappings for constant Logics.
  ///
  /// Parameters:
  /// - [module]: The module being processed
  /// - [map]: The ModuleMap for this module (kept `dynamic` to avoid
  ///   circular type dependencies with schematic_dumper)
  /// - [internalNetIds]: Map to populate with constant Logic → IDs
  /// - [ports]: The ports map (for name collision avoidance)
  /// - [nextIdRef]: Reference to the next available ID (will be mutated)
  /// - [isTop]: Whether this is the top-level module
  ConstantCollectionResult collectConstants({
    required Module module,
    required ModuleMap map,
    required Map<Logic, List<Object?>> internalNetIds,
    required Map<String, Map<String, Object?>> ports,
    required List<int> nextIdRef, // Use list as mutable reference
    required bool isTop,
    bool filterConstInputsToCombinational = false,
  }) {
    var nextId = nextIdRef[0];

    final constPatternToIds = <String, List<int>>{};
    final perInputConsts = <Logic, PerInputConstInfo>{};
    final blockedIds = <int>{};
    final blockedPatternKeys = <String>{};

    /// Helper to register a constant pattern and return its IDs.
    List<int> registerConstPattern(Const sig) {
      final patternKey = sig.value.toRadixString().split('').reversed.join();
      if (constPatternToIds.containsKey(patternKey)) {
        return constPatternToIds[patternKey]!;
      }
      final ids = List<int>.generate(sig.width, (_) => nextId++);
      constPatternToIds[patternKey] = ids;
      return ids;
    }

    // Process each child module
    for (final childMap in map.submodules.values) {
      final childModule = childMap.module;

      // Scan primitive child's internal signals for `Const` values.
      // For combinational-like primitives we allocate fresh internal IDs
      // so they do not become shared pattern-level $const cells; for
      // other primitives we register const patterns as before.
      final childPrimDesc = Primitives.instance.lookupForModule(childModule);
      final childIsPrimitive = childPrimDesc != null;
      // Only treat explicit ROHD helper modules with definitionName
      // 'Combinational' or 'Sequential' as candidates for the const-input
      // filtering behavior. We intentionally do NOT apply this logic to
      // "combinational-like" primitives or other helper modules.
      final defLower = childModule.definitionName.toLowerCase();
      final childIsCombOrSeq =
          defLower == 'combinational' || defLower == 'sequential';

      if (childIsPrimitive) {
        childModule.signals
            .whereType<Const>()
            .where((sig) => !internalNetIds.containsKey(sig))
            .forEach((sig) {
          if (filterConstInputsToCombinational && childIsCombOrSeq) {
            final ids = List<int>.generate(sig.width, (_) => nextId++);
            internalNetIds[sig] = ids;
            final patKey = sig.value.toRadixString().split('').reversed.join();
            blockedPatternKeys.add(patKey);
            if (constPatternToIds.containsKey(patKey)) {
              blockedIds.addAll(constPatternToIds[patKey]!.whereType<int>());
            }
          } else {
            internalNetIds[sig] = registerConstPattern(sig);
          }
        });
      }

      // Collect constants used by child inputs.
      final childInputs = <Logic>[];
      for (final l in childMap.portLogics.keys) {
        if (l.isInput) {
          childInputs.add(l);
        }
      }
      // Collect per-input `Const`s: process each input's srcConnections and
      // handle combinational-internalization vs per-input driver creation.
      for (final input in childInputs) {
        input.srcConnections.whereType<Const>().forEach((src) {
          final defLower2 = childModule.definitionName.toLowerCase();
          final isCombOrSeq =
              defLower2 == 'combinational' || defLower2 == 'sequential';
          if (filterConstInputsToCombinational && isCombOrSeq) {
            internalNetIds.putIfAbsent(
                src, () => List<int>.generate(src.width, (_) => nextId++));
            blockedIds.addAll(internalNetIds[src]!.whereType<int>());
            final patKey = src.value.toRadixString().split('').reversed.join();
            blockedPatternKeys.add(patKey);
            if (constPatternToIds.containsKey(patKey)) {
              blockedIds.addAll(constPatternToIds[patKey]!.whereType<int>());
            }
            return; // continue to next src
          }

          perInputConsts.putIfAbsent(input, () {
            final ids = List<int>.generate(src.width, (_) => nextId++);
            var constValue = BigInt.zero;
            for (var i = 0; i < src.width; i++) {
              if (src.value[i] == LogicValue.one) {
                constValue |= BigInt.one << i;
              }
            }
            return PerInputConstInfo(ids: ids, value: constValue);
          });
          internalNetIds[src] = perInputConsts[input]!._ids;
        });
      }

      // Scan module's own signals for `Const` values.
      module.signals
          .whereType<Const>()
          .where((sig) => !internalNetIds.containsKey(sig))
          .forEach((sig) {
        final hasScopeConsumer = sig.dstConnections.any((dst) {
          final pm = dst.parentModule;
          return pm != null && (pm == module || map.submodules.containsKey(pm));
        });
        if (isTop && !hasScopeConsumer) {
          return;
        }

        final dsts = sig.dstConnections;
        final anyToCombOrSeq = dsts.any((d) {
          final pm = d.parentModule;
          if (pm == null || !map.submodules.containsKey(pm)) {
            return false;
          }
          final pmDefLower = pm.definitionName.toLowerCase();
          return pmDefLower == 'combinational' || pmDefLower == 'sequential';
        });

        if (filterConstInputsToCombinational && anyToCombOrSeq) {
          internalNetIds[sig] = List<int>.generate(sig.width, (_) => nextId++);
          blockedIds.addAll(internalNetIds[sig]!.whereType<int>());
          final patKey = sig.value.toRadixString().split('').reversed.join();
          blockedPatternKeys.add(patKey);
          if (constPatternToIds.containsKey(patKey)) {
            blockedIds.addAll(constPatternToIds[patKey]!.whereType<int>());
          }
        } else {
          internalNetIds[sig] = registerConstPattern(sig);
        }
      });
    }

    nextIdRef[0] = nextId;
    // If any pattern-level IDs overlap with blocked IDs (from
    // internalization or per-input blocking), then mark the entire
    // pattern as blocked so we don't emit a shared $const cell.
    for (final ids in constPatternToIds.values) {
      if (ids.any(blockedIds.contains)) {
        blockedIds.addAll(ids);
      }
    }
    // Also block any patterns that were previously marked as blocked by
    // key (internalized earlier before pattern registration).
    for (final key in blockedPatternKeys) {
      final ids = constPatternToIds[key];
      if (ids != null) {
        blockedIds.addAll(ids);
      }
    }

    return ConstantCollectionResult(
      patternToIds: constPatternToIds,
      perInputConsts: perInputConsts,
      blockedIds: blockedIds,
    );
  }

  /// Emit $const cells into the cells map.
  ///
  /// Parameters:
  /// - [constResult]: The result from [collectConstants]
  /// - [cells]: The cells map to add $const cells to
  /// - [referencedIds]: Set of IDs referenced by ports and other cells
  void emitConstCells({
    required ConstantCollectionResult constResult,
    required Map<String, Map<String, Object?>> cells,
    required Set<int> referencedIds,
  }) {
    // Emit per-input $const driver cells
    for (final entry in constResult._perInputConsts.entries) {
      final info = entry.value;
      if (info._ids.isEmpty || !info._ids.any(referencedIds.contains)) {
        continue;
      }

      final verilogName = "${info.width}'h${info._value.toRadixString(16)}";
      final baseName = 'const_${info._value}';

      var cellKey = baseName;
      var suffix = 0;
      while (cells.containsKey(cellKey)) {
        suffix++;
        cellKey = '${baseName}_$suffix';
      }
      cells[cellKey] = {
        'hide_name': 1,
        'type': r'$const',
        'parameters': <String, Object?>{
          'WIDTH': info.width,
          'VALUE': info._value.toInt()
        },
        'attributes': <String, Object?>{'hide_instance_name': true},
        'port_directions': <String, String>{verilogName: 'output'},
        'connections': <String, Object?>{verilogName: info._ids}
      };
    }

    // Emit pattern-level $const cells not already materialized per-input
    for (final patternEntry in constResult._patternToIds.entries) {
      final pattern = patternEntry.key;
      final ids = patternEntry.value;
      if (ids.isEmpty || !ids.any(referencedIds.contains)) {
        continue;
      }

      // Skip if any of these ids are blocked (don't materialize $const)
      if (constResult.blockedIds.any(ids.contains)) {
        continue;
      }

      // Skip if already materialized as per-input
      final alreadyEmitted = constResult._perInputConsts.values
          .any((info) => _listEquals(info._ids, ids));
      if (alreadyEmitted) {
        continue;
      }

      final width = ids.length;
      var constValue = BigInt.zero;
      for (var i = 0; i < pattern.length; i++) {
        if (pattern[i] == '1') {
          constValue |= BigInt.one << i;
        }
      }
      final verilogValue = constValue.toRadixString(16);
      final verilogName = "$width'h$verilogValue";
      final baseName = ConstantCollectionResult.nameForPattern(pattern, ids);

      var cellKey = baseName;
      var suffix = 0;
      while (cells.containsKey(cellKey)) {
        suffix++;
        cellKey = '${baseName}_$suffix';
      }
      cells[cellKey] = {
        'hide_name': 1,
        'type': r'$const',
        'parameters': <String, Object?>{
          'WIDTH': width,
          'VALUE': constValue.toInt()
        },
        'attributes': <String, Object?>{'hide_instance_name': true},
        'port_directions': <String, String>{verilogName: 'output'},
        'connections': <String, Object?>{verilogName: ids}
      };
    }
  }

  /// Populate `netnames` with entries for constants collected in
  /// [constResult]. This adds per-input const netnames and pattern-level
  /// const netnames into the provided [netnames] map. Returns nothing; the
  /// map is mutated in-place.
  void emitConstNetnames({
    required ConstantCollectionResult constResult,
    required Map<String, Object?> netnames,
  }) {
    // First, add per-input const netnames derived from the ports they
    // drive in submodules.
    for (final entry in constResult._perInputConsts.entries) {
      final info = entry.value;
      if (info._ids.isEmpty) {
        continue;
      }
      // Use 'const_<value>' base name for netname; emitter can append a
      // suffix if collisions occur elsewhere.
      var netName = 'const_${info._value}';
      var suffix = 0;
      while (netnames.containsKey(netName)) {
        suffix++;
        netName = 'const_${info._value}_$suffix';
      }
      // Compute a pattern string for clarity (LSB index 0)
      final bits = List<String>.generate(info.width, (i) {
        final bit = ((info._value >> i) & BigInt.one) == BigInt.one ? '1' : '0';
        return bit;
      });
      final patternKey = bits.join();
      netnames[netName] = <String, Object?>{
        'bits': info._ids,
        'attributes': <String, Object?>{'const_pattern': patternKey}
      };
    }

    // Add const pattern netnames for any remaining allocated const
    // patterns that were not materialized per-input.
    for (final patternEntry in constResult._patternToIds.entries) {
      final pattern = patternEntry.key;
      final ids = patternEntry.value;
      if (ids.isEmpty) {
        continue;
      }
      // Skip if any of these ids are blocked (don't materialize netname)
      if (constResult.blockedIds.any(ids.contains)) {
        continue;
      }
      // Skip if already materialized as per-input
      final alreadyEmitted = constResult._perInputConsts.values
          .any((info) => _listEquals(info._ids, ids));
      if (alreadyEmitted) {
        continue;
      }
      final baseName = ConstantCollectionResult.nameForPattern(pattern, ids);
      var netName = baseName;
      var suffix = 0;
      while (netnames.containsKey(netName)) {
        suffix++;
        netName = '${baseName}_$suffix';
      }
      if (!netnames.containsKey(netName)) {
        netnames[netName] = <String, Object?>{
          'bits': ids,
          'attributes': <String, Object?>{'const_pattern': pattern}
        };
      }
    }
  }
}
