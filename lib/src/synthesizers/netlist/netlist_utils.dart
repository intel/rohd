// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_utils.dart
// Shared utility functions for netlist synthesis and post-processing passes.
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Shared utility functions for netlist synthesis and post-processing passes.
///
/// All methods are static — no instances are created.
class NetlistUtils {
  NetlistUtils._();

  /// Find the port name in [portMap] that corresponds to [sl].
  static String? portNameForSynthLogic(
      SynthLogic sl, Map<String, Logic> portMap) {
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
  static String? tryGetSynthLogicName(SynthLogic sl) {
    try {
      return sl.name;
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  /// Resolves [sl] to the end of its replacement chain.
  static SynthLogic resolveReplacement(SynthLogic sl) {
    var r = sl;
    while (r.replacement != null) {
      r = r.replacement!;
    }
    return r;
  }

  /// Anchored regex for range-named concat port labels like `[7:0]` or `[3]`.
  static final rangePortRe = RegExp(r'^\[(\d+)(?::(\d+))?\]$');

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

  /// Create a `$slice` cell map.
  static Map<String, Object?> makeSliceCell(
    int offset,
    int aWidth,
    int yWidth,
    List<Object> aBits,
    List<Object> yBits,
  ) =>
      <String, Object?>{
        'hide_name': 0,
        'type': r'$slice',
        'parameters': <String, Object?>{
          'OFFSET': offset,
          'A_WIDTH': aWidth,
          'Y_WIDTH': yWidth,
        },
        'attributes': <String, Object?>{},
        'port_directions': <String, String>{'A': 'input', 'Y': 'output'},
        'connections': <String, List<Object>>{'A': aBits, 'Y': yBits},
      };

  /// Build wire-driver, wire-consumer, and bit-to-net maps for a module.
  ///
  /// Scans every cell's connections to find which cell drives each wire bit
  /// (output direction) and which cells consume it (input direction).
  /// Module output-port bits are registered as pseudo-consumers (`__port__`)
  /// so that cells feeding module ports are never accidentally removed.
  static ({
    Map<int, String> wireDriverCell,
    Map<int, Set<String>> wireConsumerCells,
    Map<int, (String, List<int>)> bitToNetInfo,
  }) buildWireMaps(
    Map<String, Map<String, Object?>> cells,
    Map<String, Object?> moduleDef,
  ) {
    final wireDriverCell = <int, String>{};
    final wireConsumerCells = <int, Set<String>>{};
    for (final entry in cells.entries) {
      final cell = entry.value;
      final conns = cell['connections'] as Map<String, dynamic>? ?? {};
      final pdirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
      for (final pe in conns.entries) {
        final d = pdirs[pe.key] as String? ?? '';
        for (final b in pe.value as List) {
          if (b is int) {
            if (d == 'output') {
              wireDriverCell[b] = entry.key;
            } else if (d == 'input') {
              (wireConsumerCells[b] ??= <String>{}).add(entry.key);
            }
          }
        }
      }
    }

    final modPorts = moduleDef['ports'] as Map<String, Map<String, Object?>>?;
    if (modPorts != null) {
      for (final port in modPorts.values) {
        if ((port['direction'] as String?) == 'output') {
          for (final b in port['bits'] as List? ?? []) {
            if (b is int) {
              (wireConsumerCells[b] ??= <String>{}).add('__port__');
            }
          }
        }
      }
    }

    final netnames = moduleDef['netnames'] as Map<String, Object?>? ?? {};
    final bitToNetInfo = <int, (String, List<int>)>{};
    for (final nnEntry in netnames.entries) {
      final nd = nnEntry.value! as Map<String, Object?>;
      final bits = (nd['bits'] as List?)?.cast<int>() ?? [];
      for (final b in bits) {
        bitToNetInfo[b] = (nnEntry.key, bits);
      }
    }

    return (
      wireDriverCell: wireDriverCell,
      wireConsumerCells: wireConsumerCells,
      bitToNetInfo: bitToNetInfo,
    );
  }

  /// Trace a single wire bit backward through `$buf`/`$slice` cells,
  /// returning the ultimate source bit and the set of intermediate cell
  /// names visited along the chain.
  static (int sourceBit, Set<String> intermediates) traceBackward(
    int startBit,
    Map<int, String> wireDriverCell,
    Map<String, Map<String, Object?>> cells,
  ) {
    var current = startBit;
    final chain = <String>{};
    while (true) {
      final driverName = wireDriverCell[current];
      if (driverName == null) {
        break;
      }
      final driverCell = cells[driverName];
      if (driverCell == null) {
        break;
      }
      final dt = driverCell['type'] as String?;
      if (dt != r'$buf' && dt != r'$slice') {
        break;
      }
      if (chain.contains(driverName)) {
        break; // Cycle detected — stop tracing.
      }
      chain.add(driverName);
      final dc = driverCell['connections'] as Map<String, dynamic>? ?? {};
      if (dt == r'$buf') {
        final yBits = dc['Y'] as List;
        final aBits = dc['A'] as List;
        final idx = yBits.indexOf(current);
        if (idx < 0 || idx >= aBits.length || aBits[idx] is! int) {
          break;
        }
        current = aBits[idx] as int;
      } else {
        final yBits = dc['Y'] as List;
        final aBits = dc['A'] as List;
        final dp = driverCell['parameters'] as Map<String, Object?>? ?? {};
        final offset = dp['OFFSET'] as int? ?? 0;
        final idx = yBits.indexOf(current);
        if (idx < 0) {
          break;
        }
        final srcIdx = offset + idx;
        if (srcIdx < 0 || srcIdx >= aBits.length || aBits[srcIdx] is! int) {
          break;
        }
        current = aBits[srcIdx] as int;
      }
    }
    return (current, chain);
  }

  /// Whether every intermediate cell in [intermediates] exclusively feeds
  /// [ownerCell] or other cells in [intermediates].
  ///
  /// When [allowPortConsumers] is true, `'__port__'` pseudo-consumers are
  /// also accepted (used when module-output ports registered as consumers).
  static bool isExclusiveChain({
    required Set<String> intermediates,
    required String ownerCell,
    required Map<String, Map<String, Object?>> cells,
    required Map<int, Set<String>> wireConsumerCells,
    bool allowPortConsumers = false,
  }) {
    for (final ic in intermediates) {
      final icCell = cells[ic];
      if (icCell == null) {
        return false;
      }
      final icConns = icCell['connections'] as Map<String, dynamic>? ?? {};
      final icDirs = icCell['port_directions'] as Map<String, dynamic>? ?? {};
      for (final pe in icConns.entries) {
        if ((icDirs[pe.key] as String?) != 'output') {
          continue;
        }
        for (final b in pe.value as List) {
          if (b is! int) {
            continue;
          }
          final consumers = wireConsumerCells[b];
          if (consumers == null) {
            continue;
          }
          for (final cn in consumers) {
            if (cn != ownerCell && !intermediates.contains(cn)) {
              if (allowPortConsumers && cn == '__port__') {
                continue;
              }
              return false;
            }
          }
        }
      }
    }
    return true;
  }

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

      final resolvedOutput = resolveReplacement(outputSL);
      final resolvedInput = resolveReplacement(inputSL);

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
              SynthSubModuleInstantiation bsInst
            )>>{};

    for (final e in instance.inputMapping.entries) {
      final portName = e.key;
      if (!connections.containsKey(portName)) {
        continue; // already filtered
      }

      final resolved = resolveReplacement(e.value);
      final info = busSubsetLookup[resolved];
      if (info != null) {
        final (bsMod, rootSL, bsInst) = info;
        final width = bsMod.endIndex - bsMod.startIndex + 1;
        inputGroups
            .putIfAbsent(rootSL, () => [])
            .add((portName, bsMod.startIndex, width, bsInst));
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
      SynthSubModuleInstantiation
    )>{};
    for (final szInst in synthDef.subModuleInstantiations) {
      if (szInst.module is! Swizzle) {
        continue;
      }
      final outputSL = szInst.outputMapping.values.firstOrNull;
      if (outputSL == null) {
        continue;
      }
      final resolvedOutput = resolveReplacement(outputSL);

      // Swizzle inputs are in0, in1, ... with bit-0 first.
      var offset = 0;
      for (final inEntry in szInst.inputMapping.entries) {
        final resolvedInput = resolveReplacement(inEntry.value);
        final w = resolvedInput.width;
        swizzleLookup[resolvedInput] =
            (inEntry.key, offset, w, resolvedOutput, szInst);
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
              SynthSubModuleInstantiation szInst
            )>>{};

    for (final e in instance.outputMapping.entries) {
      final portName = e.key;
      if (!connections.containsKey(portName)) {
        continue;
      }

      final resolved = resolveReplacement(e.value);
      final info = swizzleLookup[resolved];
      if (info != null) {
        final (_, offset, width, swizzleOutputSL, szInst) = info;
        outputGroups
            .putIfAbsent(swizzleOutputSL, () => [])
            .add((portName, offset, width, szInst));
      }
    }

    // Collapse each group with > 1 contiguous member.
    for (final entry in outputGroups.entries) {
      if (entry.value.length <= 1) {
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

  /// Check if a SynthLogic is a constant (following replacement chain).
  static bool isConstantSynthLogic(SynthLogic sl) =>
      resolveReplacement(sl).isConstant;

  /// Extract the Const value from a constant SynthLogic.
  static Const? constValueFromSynthLogic(SynthLogic sl) {
    final resolved = resolveReplacement(sl);
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
