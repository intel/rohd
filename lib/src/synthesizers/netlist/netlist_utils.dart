// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_utils.dart
// Shared utility functions for netlist synthesis and post-processing passes.
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Shared utility functions for netlist synthesis and post-processing passes.
///
/// All methods are static — no instances are created.
@internal
class NetlistUtils {
  /// Prevents construction of this static utility class.
  NetlistUtils._();

  /// Find the port name in [portMap] that corresponds to [sl].
  static String? portNameForSynthLogic(
    SynthLogic sl,
    Map<String, Logic> portMap,
  ) {
    for (final e in portMap.entries) {
      if (sl.logics.contains(e.value)) {
        return e.key;
      }
    }
    return null;
  }

  /// Safely retrieve the name from a [SynthLogic], returning null if
  /// retrieval fails (e.g. name not yet picked, or the SynthLogic has
  /// been replaced).
  static String? tryGetSynthLogicName(SynthLogic sl) => sl.nameOrNull;

  /// Create a `$buf` cell map.
  static Map<String, Object?> makeBufCell(
    int width,
    List<Object> aBits,
    List<Object> yBits,
  ) =>
      <String, Object?>{
        'hide_name': 0,
        'type': r'$buf',
        'parameters': <String, Object?>{'WIDTH': width},
        'attributes': <String, Object?>{},
        'port_directions': <String, String>{'A': 'input', 'Y': 'output'},
        'connections': <String, List<Object>>{'A': aBits, 'Y': yBits},
      };

  /// Collapses bit-slice ports of a Combinational/Sequential cell into
  /// aggregate ports.
  ///
  /// **Input side**: When a Combinational references individual struct fields,
  /// each field creates a BusSubset in the parent scope, and each slice
  /// becomes a separate input port.  This method detects groups of input
  /// ports whose SynthLogics are outputs of BusSubset submodule
  /// instantiations that slice the same root signal.  For each group
  /// forming a contiguous bit range, the N individual ports are replaced
  /// with a single aggregate port connected to the corresponding sub-range
  /// of the root signal's wire IDs.
  ///
  /// **Output side**: Similarly, Combinational output ports that feed into
  /// the inputs of the same Swizzle submodule are collapsed into a single
  /// aggregate port connected to the Swizzle's output wire IDs.
  static void collapseAlwaysBlockPorts(
    SynthModuleDefinition synthDef,
    SynthSubModuleInstantiation instance,
    Map<String, String> portDirs,
    Map<String, List<Object>> connections,
    List<int> Function(SynthLogic) getIds,
  ) {
    // ── Input-side collapsing (BusSubset → Combinational) ──────────────

    // Build reverse lookup: resolved BusSubset output SynthLogic →
    //   (BusSubset module, resolved root input SynthLogic,
    //    SynthSubModuleInstantiation).
    final busSubsetLookup =
        <SynthLogic, (BusSubset, SynthLogic, SynthSubModuleInstantiation)>{};
    for (final bsInst in synthDef.subModuleInstantiations) {
      if (bsInst.module is! BusSubset) {
        continue;
      }
      final bsMod = bsInst.module as BusSubset;

      // BusSubset has input 'original' and output 'subset'
      final outputSL = bsInst.outputMapping.values.firstOrNull;
      final inputSL = bsInst.inputMapping.values.firstOrNull;
      if (outputSL == null || inputSL == null) {
        continue;
      }

      final resolvedOutput = outputSL.resolved;
      final resolvedInput = inputSL.resolved;

      busSubsetLookup[resolvedOutput] = (bsMod, resolvedInput, bsInst);
    }

    // Group input ports by root signal, also tracking the BusSubset
    // instantiations that produced each port.
    final inputGroups = <SynthLogic,
        List<
            (
              String portName,
              int startIdx,
              int width,
              SynthSubModuleInstantiation bsInst,
            )>>{};

    for (final e in instance.inputMapping.entries) {
      final portName = e.key;
      if (!connections.containsKey(portName)) {
        continue; // already filtered
      }

      final resolved = e.value.resolved;
      final info = busSubsetLookup[resolved];
      if (info != null) {
        final (bsMod, rootSL, bsInst) = info;
        final width = bsMod.endIndex - bsMod.startIndex + 1;
        inputGroups.putIfAbsent(rootSL, () => []).add((
          portName,
          bsMod.startIndex,
          width,
          bsInst,
        ));
      }
    }

    // Collapse each group with > 1 contiguous member.
    for (final entry in inputGroups.entries) {
      if (entry.value.length <= 1) {
        continue;
      }

      final rootSL = entry.key;
      final ports = entry.value..sort((a, b) => a.$2.compareTo(b.$2));

      // Verify contiguous non-overlapping coverage.
      var expectedBit = ports.first.$2;
      var contiguous = true;
      for (final (_, startIdx, width, _) in ports) {
        if (startIdx != expectedBit) {
          contiguous = false;
          break;
        }
        expectedBit += width;
      }
      if (!contiguous) {
        continue;
      }

      final minBit = ports.first.$2;
      final maxBit = ports.last.$2 + ports.last.$3 - 1;

      // Get the root signal's full wire IDs and extract the sub-range.
      final rootIds = getIds(rootSL);
      if (maxBit >= rootIds.length) {
        continue; // safety check
      }
      final aggBits = rootIds.sublist(minBit, maxBit + 1).cast<Object>();

      // Choose a name for the aggregate port.
      final rootName = tryGetSynthLogicName(rootSL) ?? 'agg_${minBit}_$maxBit';

      // Replace individual ports with the aggregate.  The bypassed
      // BusSubset cells are left in place; the post-synthesis DCE pass
      // will remove them if their outputs are no longer consumed.
      for (final (portName, _, _, _) in ports) {
        connections.remove(portName);
        portDirs.remove(portName);
      }
      connections[rootName] = aggBits;
      portDirs[rootName] = 'input';
    }

    // ── Output-side collapsing (Combinational → Swizzle) ───────────────

    // Build reverse lookup: resolved Swizzle input SynthLogic →
    //   (Swizzle port name, bit offset within the Swizzle output,
    //    port width, resolved Swizzle output SynthLogic,
    //    SynthSubModuleInstantiation).
    final swizzleLookup = <SynthLogic,
        (
      String portName,
      int offset,
      int width,
      SynthLogic,
      SynthSubModuleInstantiation,
    )>{};
    for (final szInst in synthDef.subModuleInstantiations) {
      if (szInst.module is! Swizzle) {
        continue;
      }
      final outputSL = szInst.outputMapping.values.firstOrNull;
      if (outputSL == null) {
        continue;
      }
      final resolvedOutput = outputSL.resolved;

      // Swizzle inputs are in0, in1, ... with bit-0 first.
      var offset = 0;
      for (final inEntry in szInst.inputMapping.entries) {
        final resolvedInput = inEntry.value.resolved;
        final w = resolvedInput.width;
        swizzleLookup[resolvedInput] = (
          inEntry.key,
          offset,
          w,
          resolvedOutput,
          szInst,
        );
        offset += w;
      }
    }

    // Group output ports by Swizzle output signal.
    final outputGroups = <SynthLogic,
        List<
            (
              String portName,
              int offset,
              int width,
              SynthSubModuleInstantiation szInst,
            )>>{};

    for (final e in instance.outputMapping.entries) {
      final portName = e.key;
      if (!connections.containsKey(portName)) {
        continue;
      }

      final resolved = e.value.resolved;
      final info = swizzleLookup[resolved];
      if (info != null) {
        final (_, offset, width, swizzleOutputSL, szInst) = info;
        outputGroups.putIfAbsent(swizzleOutputSL, () => []).add((
          portName,
          offset,
          width,
          szInst,
        ));
      }
    }

    // Collapse each group with > 1 contiguous member.
    for (final entry in outputGroups.entries) {
      if (entry.value.length <= 1) {
        continue;
      }

      // Skip collapsing when any member's SynthLogic is a port of the
      // parent module.  Collapsing replaces the individual output ports
      // with a single aggregate that uses the downstream Swizzle's bit
      // IDs, which would orphan the module-level port bits (they would
      // no longer be driven by any cell).
      final parentModule = synthDef.module;
      final hasModulePort = entry.value.any((member) {
        final sl = instance.outputMapping[member.$1];
        if (sl == null) {
          return false;
        }
        final resolved = sl.resolved;
        return resolved.isPort(parentModule);
      });
      if (hasModulePort) {
        continue;
      }

      final swizOutSL = entry.key;
      final ports = entry.value..sort((a, b) => a.$2.compareTo(b.$2));

      // Verify contiguous.
      var expectedBit = ports.first.$2;
      var contiguous = true;
      for (final (_, offset, width, _) in ports) {
        if (offset != expectedBit) {
          contiguous = false;
          break;
        }
        expectedBit += width;
      }
      if (!contiguous) {
        continue;
      }

      final minBit = ports.first.$2;
      final maxBit = ports.last.$2 + ports.last.$3 - 1;

      final outIds = getIds(swizOutSL);
      if (maxBit >= outIds.length) {
        continue;
      }
      final aggBits = outIds.sublist(minBit, maxBit + 1).cast<Object>();

      final outName =
          tryGetSynthLogicName(swizOutSL) ?? 'agg_out_${minBit}_$maxBit';

      // Replace individual ports with the aggregate.  The bypassed
      // Swizzle cells are left in place; the post-synthesis DCE pass
      // will remove them if their outputs are no longer consumed.
      for (final (portName, _, _, _) in ports) {
        connections.remove(portName);
        portDirs.remove(portName);
      }
      connections[outName] = aggBits;
      portDirs[outName] = 'output';
    }
  }

  /// Builds a JSON-serializable type descriptor for [logic].
  ///
  /// Returns:
  /// - For a plain [Logic] or [LogicArray]: `{'width': N}` (bitvector is the
  ///   default)
  /// - For a [LogicStructure] (non-array): `{'typeName': className, 'fields':
  ///   [field, ...]}` where each field is `{'name': fieldName, 'width': W}` for
  ///   leaf fields or `{'name': fieldName, 'type': {...}}` for nested
  ///   [LogicStructure]s.
  ///
  /// Fields are listed in LSB-to-MSB order (matching ROHD's element ordering
  /// via `rswizzle`: `elements[0]` occupies the lowest bits).
  ///
  /// When [bits] is provided, each field entry also includes a `'bits'` key
  /// containing the slice of [bits] that belongs to that field. This allows
  /// consumers to identify which net IDs map to which field even when the
  /// signal is only partially connected (where computing offsets from the flat
  /// top-level `bits` array would be ambiguous).
  static Map<String, Object?> buildLogicType(
    Logic logic, [
    List<Object>? bits,
  ]) {
    if (logic is LogicArray) {
      final result = <String, Object?>{
        'width': logic.width,
        'arrayDims': logic.dimensions,
        'elementWidth': logic.elementWidth,
      };
      // If the leaf elements are LogicStructures (array of structs),
      // include the element type metadata for recursive expansion.
      if (logic.elements.isNotEmpty) {
        final first = logic.elements.first;
        if (first is LogicStructure && first is! LogicArray) {
          result['elementType'] = buildLogicType(first);
        } else if (first is LogicArray) {
          // Nested array — encode inner dimensions via recursive call.
          result['elementType'] = buildLogicType(first);
        }
      }
      return result;
    } else if (logic is LogicStructure) {
      var offset = 0;
      final fields = logic.elements.map((e) {
        final fieldBits = bits?.sublist(offset, offset + e.width);
        offset += e.width;
        if (e is LogicStructure && e is! LogicArray) {
          return <String, Object?>{
            'name': e.name,
            if (fieldBits != null) 'bits': fieldBits,
            'type': buildLogicType(e, fieldBits),
          };
        } else if (e is LogicArray) {
          return <String, Object?>{
            'name': e.name,
            'width': e.width,
            if (fieldBits != null) 'bits': fieldBits,
            'type': buildLogicType(e, fieldBits),
          };
        } else {
          return <String, Object?>{
            'name': e.name,
            'width': e.width,
            if (fieldBits != null) 'bits': fieldBits,
          };
        }
      }).toList();
      return {'typeName': logic.runtimeType.toString(), 'fields': fields};
    } else {
      return {'width': logic.width};
    }
  }

  /// Returns the most type-specific [Logic] from [sl]'s [Logic] list for
  /// use in [buildLogicType].
  ///
  /// Prefers a [LogicStructure] (non-array) over a plain [Logic], since it
  /// carries richer field metadata.
  static Logic? typeLogicFromSynthLogic(SynthLogic sl) {
    final logics = sl.logics;
    return logics
            .whereType<LogicStructure>()
            .where((l) => l is! LogicArray)
            .firstOrNull ??
        logics.firstOrNull;
  }

  /// Check if a SynthLogic is a constant (following replacement chain).
  static bool isConstantSynthLogic(SynthLogic sl) => sl.resolved.isConstant;

  /// Extract the Const value from a constant SynthLogic.
  static Const? constValueFromSynthLogic(SynthLogic sl) {
    final resolved = sl.resolved;
    for (final logic in resolved.logics) {
      if (logic is Const) {
        return logic;
      }
    }
    return null;
  }

  /// Value portion of a constant name: `<width>_h<hex>` or `<width>_b<bin>`.
  static String constValuePart(Const c) {
    final bitChars = <String>[];
    var hasXZ = false;
    for (var i = c.width - 1; i >= 0; i--) {
      final v = c.value[i];
      switch (v) {
        case LogicValue.zero:
          bitChars.add('0');
        case LogicValue.one:
          bitChars.add('1');
        case LogicValue.x:
          bitChars.add('x');
          hasXZ = true;
        case LogicValue.z:
          bitChars.add('z');
          hasXZ = true;
      }
    }
    if (hasXZ) {
      return '${c.width}_b${bitChars.join()}';
    }
    var value = BigInt.zero;
    for (var i = c.width - 1; i >= 0; i--) {
      value = value << 1;
      if (c.value[i] == LogicValue.one) {
        value = value | BigInt.one;
      }
    }
    return '${c.width}_h${value.toRadixString(16)}';
  }
}
