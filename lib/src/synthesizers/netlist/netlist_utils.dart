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
import 'package:rohd/src/synthesizers/netlist/netlist_cell.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_port_direction.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

typedef _BusSubsetCollapseInfo = (
  BusSubset,
  SynthLogic,
  SynthSubModuleInstantiation,
);

typedef _SwizzleCollapseInfo = (
  String,
  int,
  int,
  SynthLogic,
  SynthSubModuleInstantiation,
);

/// Reusable indexes for collapsing procedural-cell ports.
@internal
class NetlistAlwaysBlockPortCollapseIndex {
  final Module _module;
  final Map<SynthLogic, _BusSubsetCollapseInfo> _busSubsets = {};
  final Map<SynthLogic, _SwizzleCollapseInfo> _swizzles = {};

  /// Indexes aggregate-producing submodules in [synthDef].
  NetlistAlwaysBlockPortCollapseIndex(SynthModuleDefinition synthDef)
      : _module = synthDef.module {
    for (final instance in synthDef.subModuleInstantiations) {
      final module = instance.module;
      if (module is BusSubset) {
        final output = instance.outputMapping.values.firstOrNull;
        final input = instance.inputMapping.values.firstOrNull;
        if (output != null && input != null) {
          _busSubsets[output.resolved] = (module, input.resolved, instance);
        }
      } else if (module is Swizzle) {
        final output = instance.outputMapping.values.firstOrNull;
        if (output == null) {
          continue;
        }

        var offset = 0;
        for (final input in instance.inputMapping.entries) {
          final resolvedInput = input.value.resolved;
          _swizzles[resolvedInput] = (
            input.key,
            offset,
            resolvedInput.width,
            output.resolved,
            instance,
          );
          offset += resolvedInput.width;
        }
      }
    }
  }
}

/// Shared utility functions for netlist synthesis and post-processing passes.
///
/// All methods are static.
@internal
abstract class NetlistUtils {
  /// Returns a deterministic cell name for an operation producing
  /// [destination].
  static String synthesizedCellName({
    required String operationName,
    required Logic destination,
  }) =>
      '${Sanitizer.sanitizeSV(operationName)}_'
      '${_destinationSuffix(destination)}';

  static String _destinationSuffix(Logic destination) {
    final module = destination.parentModule;
    if (module == null) {
      throw SynthException(
        'Cannot derive a netlist cell key for ${destination.name}: '
        'the destination has no parent module.',
      );
    }

    final parts = [
      _rootSignalIndexInModule(module, _rootLogic(destination)),
      ..._logicElementPathIndices(destination),
    ];
    return parts.map((part) => part.toString()).join('_');
  }

  static Logic _rootLogic(Logic destination) {
    var root = destination;
    while (root.parentStructure != null) {
      root = root.parentStructure!;
    }
    return root;
  }

  static List<int> _logicElementPathIndices(Logic destination) {
    final elementPath = <int>[];
    var current = destination;
    while (current.parentStructure != null) {
      final parent = current.parentStructure!;
      final index = parent.elements.indexWhere(
        (element) => identical(element, current),
      );
      elementPath.insert(0, index < 0 ? current.arrayIndex ?? 0 : index);
      current = parent;
    }
    return elementPath;
  }

  static int _rootSignalIndexInModule(Module module, Logic root) {
    final inputIndex = _identityIndex(module.inputs.values, root);
    if (inputIndex != null) {
      return inputIndex;
    }

    final outputIndex = _identityIndex(module.outputs.values, root);
    if (outputIndex != null) {
      return module.inputs.length + outputIndex;
    }

    final inOutIndex = _identityIndex(module.inOuts.values, root);
    if (inOutIndex != null) {
      return module.inputs.length + module.outputs.length + inOutIndex;
    }

    final internalIndex = _identityIndex(module.internalSignals, root);
    if (internalIndex != null) {
      return module.inputs.length +
          module.outputs.length +
          module.inOuts.length +
          internalIndex;
    }

    throw SynthException(
      'Cannot derive a netlist cell key for ${root.name}: '
      'the logic root is not registered with module ${module.name}.',
    );
  }

  static int? _identityIndex(Iterable<Logic> logics, Logic target) {
    var index = 0;
    for (final logic in logics) {
      if (identical(logic, target)) {
        return index;
      }
      index++;
    }
    return null;
  }

  /// Indexes [synthLogics] by their corresponding name in [portMap].
  static Map<SynthLogic, String> portNamesForSynthLogics(
    Iterable<SynthLogic> synthLogics,
    Map<String, Logic> portMap,
  ) {
    final namesByLogic = Map<Logic, String>.identity()
      ..addEntries(
        portMap.entries.map((entry) => MapEntry(entry.value, entry.key)),
      );
    final portNames = Map<SynthLogic, String>.identity();
    for (final synthLogic in synthLogics) {
      for (final logic in synthLogic.logics) {
        final portName = namesByLogic[logic];
        if (portName != null) {
          portNames[synthLogic] = portName;
          break;
        }
      }
    }
    return portNames;
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
      NetlistCell(
        type: r'$buf',
        parameters: <String, Object?>{'WIDTH': width},
        portDirections: {
          'A': NetlistPortDirection.input,
          'Y': NetlistPortDirection.output,
        },
        connections: <String, List<Object>>{'A': aBits, 'Y': yBits},
      ).toJson();

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
    NetlistAlwaysBlockPortCollapseIndex index,
    SynthSubModuleInstantiation instance,
    Map<String, NetlistPortDirection> portDirs,
    Map<String, List<Object>> connections,
    List<int> Function(SynthLogic) getIds,
  ) {
    // ── Input-side collapsing (BusSubset → Combinational) ──────────────

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
      final info = index._busSubsets[resolved];
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

      // Replace individual ports with the aggregate.  The bypassed BusSubset
      // cells are left in place; the post-synthesis Dead Cell Elimination pass
      // will remove them if their outputs are no longer consumed.
      for (final (portName, _, _, _) in ports) {
        connections.remove(portName);
        portDirs.remove(portName);
      }
      connections[rootName] = aggBits;
      portDirs[rootName] = NetlistPortDirection.input;
    }

    // ── Output-side collapsing (Combinational → Swizzle) ───────────────

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
      final info = index._swizzles[resolved];
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
      final hasModulePort = entry.value.any((member) {
        final sl = instance.outputMapping[member.$1];
        if (sl == null) {
          return false;
        }
        final resolved = sl.resolved;
        return resolved.isPort(index._module);
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
      portDirs[outName] = NetlistPortDirection.output;
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
    if (logic is BaseLogicArray) {
      final result = <String, Object?>{
        'width': logic.width,
        'arrayDims': logic.dimensions,
        'elementWidth': logic.elementWidth,
      };
      // If the leaf elements are LogicStructures (array of structs),
      // include the element type metadata for recursive expansion.
      if (logic.elements.isNotEmpty) {
        final first = logic.elements.first;
        if (first is LogicStructure && first is! BaseLogicArray) {
          result['elementType'] = buildLogicType(first);
        } else if (first is BaseLogicArray) {
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
        if (e is LogicStructure && e is! BaseLogicArray) {
          return <String, Object?>{
            'name': e.name,
            if (fieldBits != null) 'bits': fieldBits,
            'type': buildLogicType(e, fieldBits),
          };
        } else if (e is BaseLogicArray) {
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
            .where((l) => l is! BaseLogicArray)
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
