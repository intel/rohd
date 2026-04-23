// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synthesizer.dart
// A netlist synthesizer built on [SynthModuleDefinition].
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

///
/// Skips SystemVerilog-specific processing (chain collapsing, net connects,
/// inOut inline replacement) since netlist represents all sub-modules as
/// cells rather than inline assignment expressions.
class _NetlistSynthModuleDefinition extends SynthModuleDefinition {
  _NetlistSynthModuleDefinition(Module module) : super(module) {
    // Create explicit $slice cells for LogicArray input ports so the
    // netlist shows select gates for element extraction rather than
    // flat bit aliasing.
    module.inputs.values
        .whereType<LogicArray>()
        .forEach(_subsetReceiveArrayPort);

    // Same for LogicArray outputs on submodules (received into this scope).
    module.subModules
        .expand((sub) => sub.outputs.values)
        .whereType<LogicArray>()
        .forEach(_subsetReceiveArrayPort);

    // Create explicit $concat cells for internal LogicArrays whose elements
    // are driven independently (e.g. by constants) and then consumed by
    // submodule input ports.  This parallels what _subsetReceiveArrayPort does
    // on the decomposition side.
    final portArrays = {
      ...module.inputs.values.whereType<LogicArray>(),
      ...module.outputs.values.whereType<LogicArray>(),
      ...module.inOuts.values.whereType<LogicArray>(),
    };
    module.internalSignals
        .whereType<LogicArray>()
        .where((sig) => !portArrays.contains(sig))
        .forEach(_concatAssembleArray);
  }

  /// Creates explicit `$slice` cells for each element of a [LogicArray] port.
  ///
  /// Each element gets a [_BusSubsetForArraySlice] that extracts its bit range
  /// from the packed parent bus. This produces explicit select gates in the
  /// netlist, making array decomposition visible and traceable.
  void _subsetReceiveArrayPort(LogicArray port) {
    final portSynth = getSynthLogic(port)!;

    var idx = 0;
    for (final element in port.elements) {
      final elemSynth = getSynthLogic(element)!;
      internalSignals.add(elemSynth);

      final subsetMod = _BusSubsetForArraySlice(
        Logic(width: port.width, name: 'DUMMY'),
        idx,
        idx + element.width - 1,
      );

      getSynthSubModuleInstantiation(subsetMod)
        ..setOutputMapping(subsetMod.subset.name, elemSynth)
        ..setInputMapping(subsetMod.original.name, portSynth)

        // Pick a name now — this may be called after _pickNames() has run.
        ..pickName(module);

      idx += element.width;
    }
  }

  /// Creates an explicit `$concat` cell that assembles a [LogicArray]'s
  /// elements into the full packed array bus.
  ///
  /// This is the assembly counterpart to [_subsetReceiveArrayPort]: when
  /// individual array elements are driven independently (e.g. by constants),
  /// this makes the concatenation explicit as a visible gate in the netlist.
  void _concatAssembleArray(LogicArray array) {
    final arraySynth = getSynthLogic(array)!;

    // Build dummy signals matching each element's width.
    final dummyElements = <Logic>[];
    for (final element in array.elements) {
      dummyElements.add(Logic(width: element.width, name: 'DUMMY'));
    }

    // Pass reversed dummies so that Swizzle's internal reversal cancels out,
    // leaving in0 aligned with element[0] (LSB) and inN with element[N].
    final concatMod = _SwizzleForArrayConcat(dummyElements.reversed.toList());

    final ssmi = getSynthSubModuleInstantiation(concatMod)
      // Map the concat output to the full array.
      ..setOutputMapping(concatMod.out.name, arraySynth);

    // Map each element input.
    // Because we reversed dummies above, in0 corresponds to element[0],
    // in1 to element[1], etc.
    for (var i = 0; i < array.elements.length; i++) {
      final elemSynth = getSynthLogic(array.elements[i])!;
      internalSignals.add(elemSynth);
      final inputName = concatMod.inputs.keys.elementAt(i);
      ssmi.setInputMapping(inputName, elemSynth);
    }

    // Pick a name now — this may be called after _pickNames() has run.
    ssmi.pickName(module);
  }

  @override
  void process() {
    // No SV-specific transformations -- we want every sub-module to remain
    // as a cell in the JSON.
  }
}

/// A simple [Synthesizer] that produces netlist-compatible JSON.
///
/// Leverages [SynthModuleDefinition] for signal tracing, naming, and
/// constant resolution, then maps the resulting [SynthLogic]s to integer
/// wire-bit IDs for netlist JSON output.
///
/// Leaf modules (those with no sub-modules, or special cases like [FlipFlop])
/// do *not* get their own module definition -- they appear only as cells
/// inside their parent.
///
/// Usage:
/// ```dart
/// const options = NetlistOptions(groupStructConversions: true);
/// final synth = NetlistSynthesizer(options: options);
/// final builder = SynthBuilder(topModule, synth);
/// final json = await synth.synthesizeToJson(topModule);
/// ```
class NetlistSynthesizer extends Synthesizer {
  /// The configuration options controlling netlist synthesis.
  ///
  /// See [NetlistOptions] for documentation on individual fields.
  final NetlistOptions options;

  /// Convenience accessor for the leaf-cell mapper.
  LeafCellMapper get leafCellMapper =>
      options.leafCellMapper ?? LeafCellMapper.defaultMapper;

  /// Creates a [NetlistSynthesizer].
  ///
  /// All synthesis parameters are bundled in [options]; see
  /// [NetlistOptions] for documentation on each field.
  NetlistSynthesizer({this.options = const NetlistOptions()});

  @override
  bool generatesDefinition(Module module) =>
      // Only modules with sub-modules generate their own module definition.
      // Leaf modules (no children) become cells inside their parent.
      // FlipFlop has internal Sequential sub-modules but should be emitted as
      // a flat Yosys $dff primitive, not as a hierarchical module.
      module is! FlipFlop && module.subModules.isNotEmpty;

  @override
  SynthesisResult synthesize(
    Module module,
    String Function(Module module) getInstanceTypeOfModule, {
    SynthesisResult? Function(Module module)? lookupExistingResult,
    Map<Module, SynthesisResult>? existingResults,
  }) {
    final isTop = module.parent == null;
    final attr = <String, Object?>{'src': 'generated'};
    if (isTop) {
      attr['top'] = 1;
    }

    // -- Build SynthModuleDefinition ------------------------------------
    // This does all signal tracing, naming, constant handling,
    // assignment collapsing, and unused signal pruning.
    final canBuildSynthDef = !(module is SystemVerilog &&
        module.generatedDefinitionType == DefinitionGenerationType.none);
    final synthDef =
        canBuildSynthDef ? _NetlistSynthModuleDefinition(module) : null;

    // -- Wire-ID allocation ---------------------------------------------
    // Start wire IDs at 2 to avoid collision with Yosys constant string
    // bits "0" and "1".  JavaScript viewers coerce object keys to strings,
    // so integer wire ID 0 becomes "0", clashing with the constant-bit
    // string "0".
    var nextId = 2;

    // Map from SynthLogic -> assigned wire-bit IDs.
    final synthLogicIds = <SynthLogic, List<int>>{};

    /// Allocate or retrieve wire IDs for a [SynthLogic].
    /// For constants, do NOT follow the replacement chain to ensure each
    /// constant usage gets its own separate driver cell in netlist.
    List<int> getIds(SynthLogic sl) {
      var resolved = sl;
      // For non-constants, follow replacement chain to resolve merged logics.
      // For constants, keep them separate to create distinct const drivers.
      if (!sl.isConstant) {
        resolved = resolveReplacement(resolved);
      }
      final ids = synthLogicIds.putIfAbsent(
          resolved, () => List<int>.generate(resolved.width, (_) => nextId++));
      return ids;
    }

    // -- Ports -----------------------------------------------------------
    final ports = <String, Map<String, Object?>>{};

    final portGroups = [
      ('input', synthDef?.inputs, module.inputs),
      ('output', synthDef?.outputs, module.outputs),
      ('inout', synthDef?.inOuts, module.inOuts),
    ];
    for (final (direction, synthLogics, modulePorts) in portGroups) {
      if (synthLogics != null) {
        for (final sl in synthLogics) {
          final ids = getIds(sl);
          final portName = portNameForSynthLogic(sl, modulePorts);
          if (portName != null) {
            ports[portName] = {'direction': direction, 'bits': ids};
          }
        }
      } else {
        for (final entry in modulePorts.entries) {
          final ids = List<int>.generate(entry.value.width, (_) => nextId++);
          ports[entry.key] = {'direction': direction, 'bits': ids};
        }
      }
    }

    // -- Pre-allocate IDs for internal signals in Module order -----------
    // This ensures that internals get IDs in the same order as
    // Module.internalSignals, matching WaveformService._collectSignals.
    // Signals already allocated during the port phase are skipped by
    // putIfAbsent.  Synthesis-generated wires get IDs later (during cell
    // emission), so they are naturally appended after internals.
    //
    // Three-tier ordering guarantee:
    //   Tier 0 (ports):     inputs → outputs → inOuts        [above]
    //   Tier 1 (internals): module.internalSignals            [here]
    //   Tier 2 (synth):     cell emission wires               [below]
    if (synthDef != null) {
      module.internalSignals
          .map((sig) => synthDef.logicToSynthMap[sig])
          .whereType<SynthLogic>()
          .where((sl) => !sl.isConstant)
          .forEach(getIds);
    }

    // -- Cell emission ---------------------------------------------------
    final cells = <String, Map<String, Object?>>{};

    // Track constant SynthLogics consumed exclusively by
    // Combinational/Sequential so we can suppress their driver cells.
    final blockedConstSynthLogics = <SynthLogic>{};

    // Track emitted cell keys per instance for purging later.
    final emittedCellKeys = <SynthSubModuleInstantiation, String>{};

    if (synthDef != null) {
      for (final instance in synthDef.subModuleInstantiations) {
        if (!instance.needsInstantiation) {
          continue;
        }

        final sub = instance.module;

        final isLeaf = !generatesDefinition(sub);
        final defaultCellType =
            isLeaf ? sub.definitionName : getInstanceTypeOfModule(sub);

        // Build port directions and connections from instance mappings.
        final rawPortDirs = <String, String>{};
        final rawConnections = <String, List<Object>>{};

        for (final (dir, mapping) in [
          ('input', instance.inputMapping),
          ('output', instance.outputMapping),
          ('inout', instance.inOutMapping),
        ]) {
          for (final e in mapping.entries) {
            rawPortDirs[e.key] = dir;
            final ids = getIds(e.value);
            rawConnections[e.key] = ids.cast<Object>();
          }
        }

        // Map leaf cells to Yosys primitive types where possible.
        final mapped = isLeaf
            ? leafCellMapper.map(sub, rawPortDirs, rawConnections)
            : null;

        final cellPortDirs = mapped?.portDirs ?? rawPortDirs;
        final cellConns = mapped?.connections ?? rawConnections;

        // Use the SSMI's uniquified name as cell key to avoid
        // collisions between identically-named modules (e.g. multiple
        // struct_slice instances that share the same Module.name).
        final cellKey = instance.name;
        emittedCellKeys[instance] = cellKey;

        // -- Collapse bit-slice ports on Combinational / Sequential ----
        if (sub is Combinational || sub is Sequential) {
          collapseAlwaysBlockPorts(
            synthDef,
            instance,
            cellPortDirs,
            cellConns,
            getIds,
          );
        }

        // -- Filter constant inputs from Combinational / Sequential ----
        if (sub is Combinational || sub is Sequential) {
          final portsToRemove = <String>[];
          for (final pe in cellConns.entries) {
            final portName = pe.key;
            final synthLogic = instance.inputMapping[portName] ??
                instance.inOutMapping[portName];
            if (synthLogic != null && isConstantSynthLogic(synthLogic)) {
              portsToRemove.add(portName);
              blockedConstSynthLogics.add(synthLogic.replacement ?? synthLogic);
            }
          }
          for (final p in portsToRemove) {
            cellConns.remove(p);
            cellPortDirs.remove(p);
          }
        }

        // -- Rename Seq/Comb ports to Namer wire names -----------------
        // The port names from _Always.addInput/addOutput are internal
        // (e.g. `_out`, `_enable`).  Replace them with the Namer's
        // resolved wire name so they match SystemVerilog and WaveDumper.
        if (sub is Combinational || sub is Sequential) {
          final renames = <String, String>{};
          for (final portName in cellConns.keys.toList()) {
            final sl = instance.inputMapping[portName] ??
                instance.outputMapping[portName] ??
                instance.inOutMapping[portName];
            if (sl == null) {
              continue; // aggregated port, already renamed
            }
            final resolved = resolveReplacement(sl);
            final namerName = tryGetSynthLogicName(resolved);
            if (namerName != null && namerName != portName) {
              renames[portName] = namerName;
            }
          }
          for (final entry in renames.entries) {
            final bits = cellConns.remove(entry.key)!;
            final dir = cellPortDirs.remove(entry.key)!;
            var newName = entry.value;
            // Avoid collision with existing port names.
            if (cellConns.containsKey(newName)) {
              newName = '${entry.value}_${entry.key}';
            }
            cellConns[newName] = bits;
            cellPortDirs[newName] = dir;
          }
        }

        cells[cellKey] = {
          'hide_name': 0,
          'type': mapped?.cellType ?? defaultCellType,
          'parameters': mapped?.parameters ?? <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': cellPortDirs,
          'connections': cellConns,
        };
      }
    }

    // -- Remove cells that were cleared by collapseAlwaysBlockPorts ------
    // Because the iteration order may process a Swizzle/BusSubset cell
    // BEFORE the Combinational/Sequential that clears it, we need to purge
    // stale cells after all collapsing has been applied.
    if (synthDef != null) {
      synthDef.subModuleInstantiations
          .where((i) => !i.needsInstantiation)
          .map((i) => emittedCellKeys[i])
          .whereType<String>()
          .forEach(cells.remove);
    }

    // -- Wire-ID aliasing from remaining assignments -------------------
    // SynthModuleDefinition._collapseAssignments may leave assignments
    // between non-mergeable SynthLogics (e.g., reserved port +
    // renameable internal signal).  In SV synthesis these become
    // `assign` statements.  In netlist we need the two sides to
    // share wire IDs so that the netlist is properly connected.
    //
    // Similarly, PartialSynthAssignments for output struct ports tell
    // us which leaf-field IDs should compose the port's bits, and
    // input-struct BusSubsets (which may be pruned) tell us which
    // leaf-field IDs should be carved from the port's bits.
    final idAlias = <int, int>{};

    // Pending $struct_field cells collected during Step 3.
    // Each entry records a single field extraction from a parent struct.
    // The `parentLogic` and `fullParentIds` fields are used to group
    // entries from the same LogicStructure into a single multi-port
    // `$struct_unpack` cell.
    final structFieldCells = <({
      List<int> parentIds,
      List<int> elemIds,
      int offset,
      int width,
      Logic elemLogic,
      Logic parentLogic,
      List<int> fullParentIds,
    })>[];

    // Pending $struct_compose cells: for output struct ports, instead of
    // aliasing port bits to leaf bits (which causes "shorting"), we
    // collect composition operations and emit explicit cells later.
    // Each entry records: field (src) → port sub-range [lower:upper].
    final structComposeCells = <({
      List<int> srcIds,
      List<int> dstIds,
      int dstLowerIndex,
      int dstUpperIndex,
      SynthLogic srcSynthLogic,
      SynthLogic dstSynthLogic,
    })>[];

    // Track struct ports (both output ports of the current module AND
    // sub-module input struct ports) so Step 3 can skip $struct_field
    // collection for them ($struct_pack handles these instead).
    final outputStructPortLogics = <Logic>{};

    if (synthDef != null) {
      // 1. Non-partial assignments: src drives dst → dst IDs become
      //    src IDs (the driver's IDs are canonical).
      for (final assignment
          in synthDef.assignments.where((a) => a is! PartialSynthAssignment)) {
        final srcIds = getIds(assignment.src);
        final dstIds = getIds(assignment.dst);
        final len =
            srcIds.length < dstIds.length ? srcIds.length : dstIds.length;
        for (var i = 0; i < len; i++) {
          if (dstIds[i] != srcIds[i]) {
            idAlias[dstIds[i]] = srcIds[i];
          }
        }
      }

      // 2. Partial assignments (output / sub-module struct ports):
      //    src → dst[lower:upper].  The port-slice IDs become the
      //    leaf's IDs so that the port is composed from its fields.
      //
      //    For struct ports (both output ports of the current module
      //    AND sub-module input struct ports), we keep distinct port
      //    and field IDs and instead collect pending $struct_pack
      //    cells.  This avoids "shorting" where field wires are
      //    aliased directly to port bits, which creates multi-driver
      //    conflicts with $struct_unpack cells emitted in Step 3.
      //
      //    For non-struct sub-module input ports, we alias as before.

      /// Recursively add [struct] and all its nested [LogicStructure]
      /// descendants (excluding [LogicArray]) to [set].
      void addStructAndDescendants(LogicStructure struct, Set<Logic> set) {
        set.add(struct);
        for (final elem in struct.elements) {
          if (elem is LogicStructure && elem is! LogicArray) {
            addStructAndDescendants(elem, set);
          }
        }
      }

      for (final pa
          in synthDef.assignments.whereType<PartialSynthAssignment>()) {
        final srcIds = getIds(pa.src);
        final dstIds = getIds(pa.dst);

        // Detect: is pa.dst an output struct port of the current module?
        final isCurrentModuleOutputPort =
            pa.dst.isPort(module) && pa.dst.logics.any((l) => l.isOutput);

        // Detect: is pa.dst a sub-module input struct port?
        // (LogicStructure but not LogicArray, and not an output of the
        // current module.)
        final isSubModuleInputStructPort = !isCurrentModuleOutputPort &&
            pa.dst.logics.any((l) => l is LogicStructure && l is! LogicArray);

        if (isCurrentModuleOutputPort || isSubModuleInputStructPort) {
          // Record as pending compose cell instead of aliasing.
          structComposeCells.add((
            srcIds: srcIds,
            dstIds: dstIds,
            dstLowerIndex: pa.dstLowerIndex,
            dstUpperIndex: pa.dstUpperIndex,
            srcSynthLogic: pa.src,
            dstSynthLogic: pa.dst,
          ));
          // Track the Logic (and nested structs) so Step 3 skips
          // $struct_unpack for them.
          for (final l in pa.dst.logics) {
            if (l is LogicStructure && l is! LogicArray) {
              addStructAndDescendants(l, outputStructPortLogics);
            }
          }
        } else {
          // Non-struct sub-module input port: alias as before.
          for (var i = 0; i < srcIds.length; i++) {
            final dstIdx = pa.dstLowerIndex + i;
            if (dstIdx < dstIds.length && dstIds[dstIdx] != srcIds[i]) {
              idAlias[dstIds[dstIdx]] = srcIds[i];
            }
          }
        }
      }

      // 3. LogicStructure and LogicArray: child IDs → parent-slice IDs.
      //
      //    LogicArray elements alias their IDs to matching parent bits
      //    so array connectivity works.
      //
      //    Non-array LogicStructure elements are NOT aliased.  Instead,
      //    their parent→element mappings are collected in
      //    [structFieldCells] and emitted as explicit $struct_field
      //    cells after alias resolution.  This preserves element signals
      //    (e.g. "a_mantissa") as distinct named wires visible in the
      //    schematic, rather than collapsing them into parent bit ranges.
      //
      //    For arrays with explicit $slice/$concat cells (from
      //    _BusSubsetForArraySlice / _SwizzleForArrayConcat), aliasing
      //    is skipped entirely — the cells provide the structural link.
      //
      //    Applied to ALL instances (ports AND internal signals) since
      //    internal arrays/structs (e.g. constant-driven coefficients)
      //    also need child→parent aliasing.
      //
      //    - LogicStructure (non-array): walks leafElements (recursive)
      //    - LogicArray: walks elements (direct children only, since
      //      each element is already a flat bitvector).
      //      For input array ports that have _BusSubsetForArraySlice
      //      cells, we skip aliasing so the $slice cells provide the
      //      structural connection (see _subsetReceiveArrayPort).
      //
      //    When a child ID was already aliased (e.g. by step 1 to a
      //    constant driver), we also redirect that prior target to the
      //    parent ID so the transitive chain resolves correctly:
      //    constId → childId → parentId.
      void aliasChildToParent(int childId, int parentId) {
        if (childId == parentId) {
          return;
        }
        // If childId already aliases somewhere (e.g. constId → childId
        // was set in step 1 as childId → constId), redirect that old
        // target to parentId as well, so constId → parentId.
        final existing = idAlias[childId];
        if (existing != null && existing != parentId) {
          idAlias[existing] = parentId;
        }
        idAlias[childId] = parentId;
      }

      // Collect LogicArray ports that have explicit array_slice or
      // array_concat submodules so we can skip aliasing them (the
      // $slice/$concat cells provide the structural link).
      final arraysWithExplicitCells = <Logic>{};
      for (final inst in synthDef.subModuleInstantiations) {
        if (inst.module is _BusSubsetForArraySlice) {
          // The input of the BusSubset is the array port.
          for (final inputSL in inst.inputMapping.values) {
            final logic = synthDef.logicToSynthMap.entries
                .where(
                    (e) => e.value == inputSL || e.value.replacement == inputSL)
                .map((e) => e.key)
                .firstOrNull;
            if (logic != null && logic is LogicArray) {
              arraysWithExplicitCells.add(logic);
            }
            // Also check the resolved replacement chain.
            final resolved = resolveReplacement(inputSL);
            final logic2 = synthDef.logicToSynthMap.entries
                .where((e) => e.value == resolved)
                .map((e) => e.key)
                .firstOrNull;
            if (logic2 != null && logic2 is LogicArray) {
              arraysWithExplicitCells.add(logic2);
            }
          }
        }
        if (inst.module is _SwizzleForArrayConcat) {
          // The output of the Swizzle is the array signal.
          for (final outputSL in inst.outputMapping.values) {
            final logic = synthDef.logicToSynthMap.entries
                .where((e) =>
                    e.value == outputSL || e.value.replacement == outputSL)
                .map((e) => e.key)
                .firstOrNull;
            if (logic != null && logic is LogicArray) {
              arraysWithExplicitCells.add(logic);
            }
          }
        }
      }

      for (final entry in synthDef.logicToSynthMap.entries) {
        final logic = entry.key;
        if (logic is! LogicStructure) {
          continue;
        }
        final parentSL = entry.value;
        final parentIds = getIds(parentSL);

        if (logic is LogicArray) {
          // Skip aliasing for arrays that have explicit $slice/$concat cells.
          if (arraysWithExplicitCells.contains(logic)) {
            continue;
          }
          // Array: alias each element's IDs to matching parent slice.
          var idx = 0;
          for (final element in logic.elements) {
            final elemSL = synthDef.logicToSynthMap[element];
            if (elemSL != null) {
              final elemIds = getIds(elemSL);
              for (var i = 0;
                  i < elemIds.length && idx + i < parentIds.length;
                  i++) {
                aliasChildToParent(elemIds[i], parentIds[idx + i]);
              }
            }
            idx += element.width;
          }
        } else {
          // Struct: collect element→parent mappings for $struct_field
          // cell emission instead of aliasing.  This preserves named
          // field signals as distinct wires connected through explicit
          // cells, making them visible in the schematic and evaluable
          // by the netlist evaluator.
          //
          // Skip output struct ports of the current module — those are
          // handled by $struct_compose cells (from Step 2).
          if (outputStructPortLogics.contains(logic)) {
            continue;
          }
          var idx = 0;
          for (final elem in logic.elements) {
            final elemSL = synthDef.logicToSynthMap[elem];
            if (elemSL != null) {
              final elemIds = getIds(elemSL);
              final sliceLen = elemIds.length < parentIds.length - idx
                  ? elemIds.length
                  : parentIds.length - idx;
              if (sliceLen > 0) {
                structFieldCells.add((
                  parentIds: parentIds.sublist(idx, idx + sliceLen),
                  elemIds: elemIds.sublist(0, sliceLen),
                  offset: idx,
                  width: sliceLen,
                  elemLogic: elem,
                  parentLogic: logic,
                  fullParentIds: parentIds,
                ));
              }
            }
            idx += elem.width;
          }
        }
      }
    }

    // Transitively resolve an alias chain to its canonical ID.
    // Uses a visited set to detect cycles created by conflicting
    // child→parent and assignment aliasing directions.
    int resolveAlias(int id) {
      var resolved = id;
      final visited = <int>{};
      while (idAlias.containsKey(resolved)) {
        if (!visited.add(resolved)) {
          // Cycle detected — break the cycle by removing this entry.
          idAlias.remove(resolved);
          break;
        }
        resolved = idAlias[resolved]!;
      }
      return resolved;
    }

    // Apply aliases to a list of bit IDs / string constants.
    List<Object> applyAlias(List<Object> bits) =>
        bits.map((b) => b is int ? resolveAlias(b) : b).toList();

    // Alias port bits.
    if (idAlias.isNotEmpty) {
      for (final p in ports.values) {
        p['bits'] = applyAlias((p['bits']! as List).cast<Object>());
      }
      // Alias cell connections.
      for (final c in cells.values) {
        final conns = c['connections']! as Map<String, dynamic>;
        for (final key in conns.keys.toList()) {
          conns[key] = applyAlias((conns[key] as List).cast<Object>());
        }
      }

      // -- Elide trivial $slice cells ----------------------------------
      // Also elide struct_slice cells (`_BusSubsetForStructSlice`
      // instances from `_subsetReceiveStructPort`) because the new
      // `$struct_unpack` cells emitted below supersede them with
      // better-named field-level connections.
      cells.removeWhere((cellKey, cell) {
        if (cell['type'] != r'$slice') {
          return false;
        }
        // Unconditionally remove struct_slice cells — they are
        // duplicated by $struct_unpack cells which carry field names.
        if (cellKey.startsWith('struct_slice')) {
          return true;
        }
        final params = cell['parameters'] as Map<String, Object?>?;
        final offset = params?['OFFSET'];
        if (offset is! int) {
          return false;
        }
        final conns = cell['connections']! as Map<String, dynamic>;
        final aBits = conns['A'] as List?;
        final yBits = conns['Y'] as List?;
        if (aBits == null || yBits == null) {
          return false;
        }
        return yBits.indexed.every((e) =>
            offset + e.$1 < aBits.length && e.$2 == aBits[offset + e.$1]);
      });
    }

    // -- Emit $struct_unpack cells for LogicStructure elements ----------
    // Group per-field entries by their parent LogicStructure and emit a
    // single multi-port cell per group.  Each group has:
    //   • input port A: the full parent bus (packed bitvector)
    //   • one output port per non-trivial field: bits for that field
    // This replaces the old per-field $struct_field cells.
    if (synthDef != null && structFieldCells.isNotEmpty) {
      // Group by parent Logic identity.
      final groups = <Logic,
          List<
              ({
                List<int> parentIds,
                List<int> elemIds,
                int offset,
                int width,
                Logic elemLogic,
                Logic parentLogic,
                List<int> fullParentIds,
              })>>{};
      for (final sf in structFieldCells) {
        (groups[sf.parentLogic] ??= []).add(sf);
      }

      var suIdx = 0;
      for (final entry in groups.entries) {
        final parentLogic = entry.key;
        final fields = entry.value;
        final fullParentIds = fields.first.fullParentIds;
        final resolvedParentBits = applyAlias(fullParentIds.cast<Object>());

        // Filter out trivial fields (input slice == output after aliasing).
        final nonTrivialFields = fields
            .map((sf) {
              final resolvedElemBits = applyAlias(sf.elemIds.cast<Object>());
              return (
                resolvedElemBits: resolvedElemBits,
                offset: sf.offset,
                width: sf.width,
                elemLogic: sf.elemLogic,
              );
            })
            .where((f) => !f.resolvedElemBits.indexed.every((e) {
                  final (i, bit) = e;
                  return f.offset + i < resolvedParentBits.length &&
                      bit == resolvedParentBits[f.offset + i];
                }))
            .toList();

        if (nonTrivialFields.isEmpty) {
          continue;
        }

        // Derive struct name for the cell key.
        final structName = Sanitizer.sanitizeSV(parentLogic.name);

        // Build element range table for the parent struct so we can
        // derive proper field names even when the leaf Logic objects
        // have unpreferred names like `_swizzled`.
        // Same strategy as $struct_pack: walk the hierarchy collecting
        // (start, end, name, path, indexInParent) and look up the
        // narrowest non-unpreferred range for each field offset.
        final suElementRanges = <({
          int start,
          int end,
          String name,
          String path,
          int indexInParent,
        })>[];
        if (parentLogic is LogicStructure) {
          void walkStruct(
              LogicStructure struct, int baseOffset, String parentPath) {
            var offset = baseOffset;
            for (var idx = 0; idx < struct.elements.length; idx++) {
              final elem = struct.elements[idx];
              final elemEnd = offset + elem.width;
              final elemPath =
                  parentPath.isEmpty ? elem.name : '${parentPath}_${elem.name}';
              suElementRanges.add((
                start: offset,
                end: elemEnd,
                name: elem.name,
                path: elemPath,
                indexInParent: idx,
              ));
              if (elem is LogicStructure && elem is! LogicArray) {
                walkStruct(elem, offset, elemPath);
              }
              offset = elemEnd;
            }
          }

          walkStruct(parentLogic, 0, '');
        }

        String suFieldNameFor(int fieldOffset, String fallbackName) {
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? bestNamed;
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? bestAny;
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? narrowest;

          for (final r in suElementRanges) {
            if (fieldOffset >= r.start && fieldOffset < r.end) {
              final span = r.end - r.start;
              if (narrowest == null ||
                  span < (narrowest.end - narrowest.start)) {
                narrowest = r;
              }
              if (bestAny == null || span < (bestAny.end - bestAny.start)) {
                bestAny = r;
              }
              if (!Naming.isUnpreferred(r.name)) {
                if (bestNamed == null ||
                    span < (bestNamed.end - bestNamed.start)) {
                  bestNamed = r;
                }
              }
            }
          }

          if (bestNamed != null) {
            if (narrowest != null &&
                (narrowest.end - narrowest.start) <
                    (bestNamed.end - bestNamed.start)) {
              final bestNamedPrefix = bestNamed.path;
              if (narrowest.path.length > bestNamedPrefix.length &&
                  narrowest.path.startsWith(bestNamedPrefix)) {
                final suffix =
                    narrowest.path.substring(bestNamedPrefix.length + 1);
                if (!Naming.isUnpreferred(suffix)) {
                  return '${bestNamed.name}_$suffix';
                }
              }
              return '${bestNamed.name}_${narrowest.indexInParent}';
            }
            return bestNamed.name;
          }
          // All matching elements have unpreferred names — use the
          // narrowest element's positional index as discriminator.
          if (narrowest != null && Naming.isUnpreferred(narrowest.name)) {
            return 'anonymous_${narrowest.indexInParent}';
          }
          return bestAny?.name ?? fallbackName;
        }

        // Build port_directions and connections with one output per field.
        final portDirs = <String, String>{'A': 'input'};
        final conns = <String, List<Object>>{'A': resolvedParentBits};

        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          final fieldName = suFieldNameFor(f.offset, f.elemLogic.name);
          // Disambiguate duplicate field names with index suffix.
          var portName = fieldName;
          if (portDirs.containsKey(portName)) {
            portName = '${fieldName}_$i';
          }
          portDirs[portName] = 'output';
          conns[portName] = f.resolvedElemBits;
        }

        // Parameters list field metadata for the schematic viewer.
        final params = <String, Object?>{
          'STRUCT_NAME': parentLogic.name,
          'FIELD_COUNT': nonTrivialFields.length,
        };
        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          params['FIELD_${i}_NAME'] =
              suFieldNameFor(f.offset, f.elemLogic.name);
          params['FIELD_${i}_OFFSET'] = f.offset;
          params['FIELD_${i}_WIDTH'] = f.width;
        }

        cells['struct_unpack_${suIdx}_$structName'] = {
          'hide_name': 0,
          'type': r'$struct_unpack',
          'parameters': params,
          'attributes': <String, Object?>{},
          'port_directions': portDirs,
          'connections': conns,
        };
        suIdx++;
      }
    }

    // -- Emit $struct_pack cells for output struct ports ------------------
    // Group compose entries by destination port and emit a single
    // multi-port cell per group.  Each group has:
    //   • one input port per non-trivial field
    //   • output port Y: the full packed output bus
    // This replaces the old per-field $struct_compose cells.
    if (structComposeCells.isNotEmpty) {
      // Group by destination SynthLogic identity.
      final composeGroups = <SynthLogic,
          List<
              ({
                List<int> srcIds,
                List<int> dstIds,
                int dstLowerIndex,
                int dstUpperIndex,
                SynthLogic srcSynthLogic,
                SynthLogic dstSynthLogic,
              })>>{};
      for (final sc in structComposeCells) {
        (composeGroups[sc.dstSynthLogic] ??= []).add(sc);
      }

      var spIdx = 0;
      for (final entry in composeGroups.entries) {
        final dstSynthLogic = entry.key;
        final fields = entry.value;
        final resolvedDstBits = applyAlias(fields.first.dstIds.cast<Object>());

        // Filter out trivial fields.
        final nonTrivialFields = fields
            .map((sc) {
              final resolvedSrcBits = applyAlias(sc.srcIds.cast<Object>());
              final yBits = resolvedDstBits.sublist(
                  sc.dstLowerIndex, sc.dstUpperIndex + 1);
              return (
                resolvedSrcBits: resolvedSrcBits,
                yBits: yBits,
                dstLowerIndex: sc.dstLowerIndex,
                dstUpperIndex: sc.dstUpperIndex,
                srcSynthLogic: sc.srcSynthLogic,
              );
            })
            .where((f) => !f.resolvedSrcBits
                .take(f.yBits.length)
                .indexed
                .every((e) => e.$2 == f.yBits[e.$1]))
            .toList();

        if (nonTrivialFields.isEmpty) {
          continue;
        }

        // Derive struct name from the destination Logic.
        final dstLogic = dstSynthLogic.logics.firstOrNull;
        final structName = dstLogic != null
            ? Sanitizer.sanitizeSV(dstLogic.name)
            : 'struct_$spIdx';

        // Build a lookup from bit offset to the best struct element
        // name, so that field names come from the struct definition
        // (e.g. "data", "last", "poison") rather than the source
        // signal name (which may be an internal like "_swizzled").
        //
        // Elements pack LSB-first via `rswizzle`, so element[0]
        // starts at offset 0, element[1] at element[0].width, etc.
        //
        // We collect (start, end, name, path, parentElementIndex)
        // ranges for every element at every nesting level.  The
        // `path` carries the chain of parent struct names so we can
        // produce qualified names like "mmu_info_mmuSid".  When
        // leaf names are unpreferred, `parentElementIndex` provides
        // a fallback discriminator like "mmu_info_0".
        final dstElementRanges = <({
          int start,
          int end,
          String name,
          String path,
          int indexInParent,
        })>[];
        if (dstLogic is LogicStructure) {
          void walkStruct(
              LogicStructure struct, int baseOffset, String parentPath) {
            var offset = baseOffset;
            for (var idx = 0; idx < struct.elements.length; idx++) {
              final elem = struct.elements[idx];
              final elemEnd = offset + elem.width;
              final elemPath =
                  parentPath.isEmpty ? elem.name : '${parentPath}_${elem.name}';
              dstElementRanges.add((
                start: offset,
                end: elemEnd,
                name: elem.name,
                path: elemPath,
                indexInParent: idx,
              ));
              if (elem is LogicStructure && elem is! LogicArray) {
                walkStruct(elem, offset, elemPath);
              }
              offset = elemEnd;
            }
          }

          walkStruct(dstLogic, 0, '');
        }

        /// Look up the field name for a compose entry by finding the
        /// best struct element whose range contains [dstLowerIndex].
        ///
        /// Strategy (deepest-first):
        ///  1. Find the narrowest element with a non-unpreferred name.
        ///  2. If a narrower unpreferred leaf exists under a named
        ///     parent, try to qualify with the leaf's proper name
        ///     (e.g. `mmu_info_mmuSid`).
        ///  3. If the leaf name is also unpreferred, fall back to the
        ///     parent name qualified by the leaf's positional index
        ///     (e.g. `mmu_info_0`, `mmu_info_1`).
        ///  4. Falls back to the resolved source SynthLogic name.
        String fieldNameFor(
          int dstLowerIndex,
          SynthLogic srcSynthLogic,
        ) {
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? bestNamed;
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? bestAny;
          ({
            int start,
            int end,
            String name,
            String path,
            int indexInParent,
          })? narrowest;

          for (final r in dstElementRanges) {
            if (dstLowerIndex >= r.start && dstLowerIndex < r.end) {
              final span = r.end - r.start;
              if (narrowest == null ||
                  span < (narrowest.end - narrowest.start)) {
                narrowest = r;
              }
              if (bestAny == null || span < (bestAny.end - bestAny.start)) {
                bestAny = r;
              }
              if (!Naming.isUnpreferred(r.name)) {
                if (bestNamed == null ||
                    span < (bestNamed.end - bestNamed.start)) {
                  bestNamed = r;
                }
              }
            }
          }

          if (bestNamed != null) {
            // Check if there's a narrower child element under
            // bestNamed that we can use to discriminate.
            if (narrowest != null &&
                (narrowest.end - narrowest.start) <
                    (bestNamed.end - bestNamed.start)) {
              final bestNamedPrefix = bestNamed.path;
              // Try using the child's proper name as qualifier.
              if (narrowest.path.length > bestNamedPrefix.length &&
                  narrowest.path.startsWith(bestNamedPrefix)) {
                final suffix =
                    narrowest.path.substring(bestNamedPrefix.length + 1);
                if (!Naming.isUnpreferred(suffix)) {
                  return '${bestNamed.name}_$suffix';
                }
              }
              // Child has unpreferred name — use positional index.
              return '${bestNamed.name}_${narrowest.indexInParent}';
            }
            return bestNamed.name;
          }
          return bestAny?.name ?? resolveReplacement(srcSynthLogic).name;
        }

        // Build port_directions and connections.
        final portDirs = <String, String>{};
        final conns = <String, List<Object>>{};

        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          final fieldName = fieldNameFor(f.dstLowerIndex, f.srcSynthLogic);
          var portName = fieldName;
          if (portDirs.containsKey(portName)) {
            portName = '${fieldName}_$i';
          }
          portDirs[portName] = 'input';
          conns[portName] = f.resolvedSrcBits;
        }

        // Output port Y: full destination bus.
        portDirs['Y'] = 'output';
        conns['Y'] = resolvedDstBits;

        // Parameters list field metadata for the schematic viewer.
        final params = <String, Object?>{
          'STRUCT_NAME': dstLogic?.name ?? 'struct',
          'FIELD_COUNT': nonTrivialFields.length,
        };
        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          params['FIELD_${i}_NAME'] =
              fieldNameFor(f.dstLowerIndex, f.srcSynthLogic);
          params['FIELD_${i}_OFFSET'] = f.dstLowerIndex;
          params['FIELD_${i}_WIDTH'] = f.dstUpperIndex - f.dstLowerIndex + 1;
        }

        cells['struct_pack_${spIdx}_$structName'] = {
          'hide_name': 0,
          'type': r'$struct_pack',
          'parameters': params,
          'attributes': <String, Object?>{},
          'port_directions': portDirs,
          'connections': conns,
        };
        spIdx++;
      }
    }

    // -- Passthrough buffer insertion ------------------------------------
    // When a signal passes directly from an input port to an output port,
    // they share the same wire IDs after aliasing.  This causes the signal
    // to appear routed *around* the module in the netlist rather than
    // *through* it.  Insert a `$buf` cell to break the wire-ID sharing,
    // giving the output port fresh IDs driven by the buffer.
    {
      final inputBitIds = ports.values
          .where((p) => p['direction'] == 'input' || p['direction'] == 'inout')
          .expand((p) => p['bits']! as List)
          .whereType<int>()
          .toSet();

      // Check each output port for overlap with input bits.
      var bufIdx = 0;
      for (final p
          in ports.entries.where((p) => p.value['direction'] == 'output')) {
        final outBits = (p.value['bits']! as List).cast<Object>();
        if (!outBits.any((b) => b is int && inputBitIds.contains(b))) {
          continue;
        }

        // Allocate fresh wire IDs for the output side of the buffer.
        final freshBits =
            List<Object>.generate(outBits.length, (_) => nextId++);

        // Insert a $buf cell: input = original (shared) IDs,
        // output = fresh IDs.
        cells['passthrough_buf_$bufIdx'] =
            makeBufCell(outBits.length, outBits, freshBits);

        // Update the output port to use the fresh IDs.
        p.value['bits'] = freshBits;
        bufIdx++;
      }
    }

    // -- Dead-cell elimination (DCE) -------------------------------------
    // After aliasing and elision, some cells may have inputs whose wire
    // IDs are not driven by any cell output or module input port.  This
    // typically happens when a LogicStructure's `packed` representation
    // creates a Swizzle chain whose inputs reference sub-module-internal
    // signals that are not accessible from the synthesised module's
    // scope.  Iteratively remove such dead cells using both forward
    // (all-inputs-undriven) and backward (all-outputs-unconsumed) DCE.
    if (options.enableDCE) {
      var dceChanged = true;
      while (dceChanged) {
        dceChanged = false;

        // Build set of driven wire IDs (from input/inout ports and cell
        // outputs).
        final drivenIds = <int>{
          ...ports.values
              .where(
                  (p) => p['direction'] == 'input' || p['direction'] == 'inout')
              .expand((p) => p['bits']! as List)
              .whereType<int>(),
          ...cells.values.expand((c) {
            final cell = c as Map<String, dynamic>;
            final conns = cell['connections']! as Map<String, dynamic>;
            final pdirs = cell['port_directions']! as Map<String, dynamic>;
            return conns.entries
                .where((pe) => pdirs[pe.key] == 'output')
                .expand((pe) => pe.value as List)
                .whereType<int>();
          }),
        };

        // Build set of consumed wire IDs (from output/inout ports and
        // cell inputs).
        final consumedIds = <int>{
          ...ports.values
              .where((p) =>
                  p['direction'] == 'output' || p['direction'] == 'inout')
              .expand((p) => p['bits']! as List)
              .whereType<int>(),
          ...cells.values.expand((c) {
            final cell = c as Map<String, dynamic>;
            final conns = cell['connections']! as Map<String, dynamic>;
            final pdirs = cell['port_directions']! as Map<String, dynamic>;
            return conns.entries
                .where((pe) => pdirs[pe.key] == 'input')
                .expand((pe) => pe.value as List)
                .whereType<int>();
          }),
        };

        // Forward DCE: remove cells whose inputs are ALL undriven.
        cells
          ..removeWhere((cellKey, cellVal) {
            final cell = cellVal as Map<String, dynamic>;
            final conns = cell['connections']! as Map<String, dynamic>;
            final pdirs = cell['port_directions']! as Map<String, dynamic>;
            final inputPorts =
                conns.entries.where((pe) => pdirs[pe.key] == 'input');
            if (inputPorts.isEmpty) {
              return false;
            }
            final allUndriven = !inputPorts
                .expand((pe) => pe.value as List)
                .any((b) => (b is int && drivenIds.contains(b)) || b is String);
            if (allUndriven) {
              dceChanged = true;
              return true;
            }
            return false;
          })

          // Backward DCE: remove cells whose outputs are ALL unconsumed.
          // Preserve non-leaf cells (user module instances) — their type
          // does not start with '$' (Yosys primitive convention).  Users
          // expect to see all instantiated modules in the schematic even
          // when outputs are unconnected.
          ..removeWhere((cellKey, cellVal) {
            final cell = cellVal as Map<String, dynamic>;
            final cellType = cell['type'] as String? ?? '';
            if (!cellType.startsWith(r'$')) {
              return false;
            }
            final conns = cell['connections']! as Map<String, dynamic>;
            final pdirs = cell['port_directions']! as Map<String, dynamic>;
            final outputPorts =
                conns.entries.where((pe) => pdirs[pe.key] == 'output');
            if (outputPorts.isEmpty) {
              return false;
            }
            final allUnconsumed = !outputPorts
                .expand((pe) => pe.value as List)
                .whereType<int>()
                .any(consumedIds.contains);
            if (allUnconsumed) {
              dceChanged = true;
              return true;
            }
            return false;
          });
      }
    }

    // -- Constant driver cells -------------------------------------------
    // Generated AFTER the aliasing pass so that constants discovered
    // during aliasing (via getIds(assignment.src)) are included.
    // Constant IDs may have been redirected by step 3 (struct/array
    // child→parent aliasing), so apply alias resolution to their
    // connection bits.
    {
      var constIdx = 0;
      final emittedConstWires = <int>{};
      for (final entry in synthLogicIds.entries
          .where((e) => e.key.isConstant)
          .where((e) => !blockedConstSynthLogics.contains(e.key))
          .where((e) => e.value.isNotEmpty)) {
        final sl = entry.key;
        final constValue = constValueFromSynthLogic(sl);
        if (constValue == null) {
          continue;
        }
        final ids = entry.value;

        // Resolve aliases and skip if these wires are already driven
        // by a previously emitted $const cell (can happen when aliasing
        // merges two SynthLogic constants onto the same wire IDs).
        final resolvedIds = applyAlias(ids.cast<Object>());
        final firstWire =
            resolvedIds.firstWhere((b) => b is int, orElse: () => -1);
        if (firstWire is int && firstWire >= 0) {
          if (emittedConstWires.contains(firstWire)) {
            continue;
          }
          emittedConstWires.addAll(resolvedIds.whereType<int>());
        }

        final valuePart = constValuePart(constValue);
        final cellName = 'const_${constIdx}_$valuePart';
        final valueLiteral = valuePart.replaceFirst('_', "'");

        cells[cellName] = {
          'hide_name': 0,
          'type': r'$const',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, String>{valueLiteral: 'output'},
          'connections': <String, List<Object>>{
            valueLiteral: resolvedIds,
          },
        };
        constIdx++;
      }
    }

    // -- Remove floating $const cells ------------------------------------
    // The $const cells were emitted after the main DCE pass, so they
    // may reference wire IDs that no cell input or output port consumes.
    if (options.enableDCE) {
      final consumedByInputs = <int>{
        ...ports.values
            .where(
                (p) => p['direction'] == 'output' || p['direction'] == 'inout')
            .expand((p) => p['bits']! as List)
            .whereType<int>(),
        ...cells.values.expand((c) {
          final cell = c as Map<String, dynamic>;
          final conns = cell['connections']! as Map<String, dynamic>;
          final pdirs = cell['port_directions']! as Map<String, dynamic>;
          return conns.entries
              .where((pe) => pdirs[pe.key] == 'input')
              .expand((pe) => pe.value as List)
              .whereType<int>();
        }),
      };

      cells.removeWhere((cellKey, cellVal) {
        final cell = cellVal as Map<String, dynamic>;
        if (cell['type'] != r'$const') {
          return false;
        }
        final conns = cell['connections']! as Map<String, dynamic>;
        final pdirs = cell['port_directions']! as Map<String, dynamic>;
        return !conns.entries
            .where((pe) => pdirs[pe.key] == 'output')
            .expand((pe) => pe.value as List)
            .whereType<int>()
            .any(consumedByInputs.contains);
      });
    }

    // -- Break shared wire IDs for array_concat cells --------------------
    // After aliasing, the concat inputs share the same wire IDs as the
    // concat Y output (because LogicArray elements share the parent's
    // bit storage).  This makes the concat transparent -- constants
    // appear to drive the parent array directly.
    //
    // To fix: allocate fresh wire IDs for each concat input port,
    // then redirect all other cells whose outputs used those old IDs
    // to drive the fresh IDs instead.  The concat Y output keeps the
    // original parent-array IDs, so the data flow becomes:
    //   const → fresh_IDs → concat input → concat Y (= parent IDs)
    final arrayConcatOldToNew = <int, int>{};

    for (final cellEntry in cells.entries) {
      if (!cellEntry.key.startsWith('array_concat')) {
        continue;
      }
      final cell = cellEntry.value as Map<String, dynamic>;
      final conns = cell['connections'] as Map<String, dynamic>;
      final dirs = cell['port_directions'] as Map<String, dynamic>;

      for (final portEntry in conns.entries.toList()) {
        if (dirs[portEntry.key] != 'input') {
          continue;
        }
        final oldBits = (portEntry.value as List).cast<Object>();
        conns[portEntry.key] = [
          for (final b in oldBits)
            b is int ? arrayConcatOldToNew.putIfAbsent(b, () => nextId++) : b,
        ];
      }
    }

    // Redirect other cells: any output port bit that matches an old ID
    // gets replaced with the corresponding fresh ID.
    if (arrayConcatOldToNew.isNotEmpty) {
      for (final cellEntry in cells.entries) {
        if (cellEntry.key.startsWith('array_concat')) {
          continue; // skip the concat cells themselves
        }
        final cell = cellEntry.value as Map<String, dynamic>;
        final conns = cell['connections'] as Map<String, dynamic>;
        final dirs = cell['port_directions'] as Map<String, dynamic>;

        for (final portEntry in conns.entries.toList()) {
          if (dirs[portEntry.key] != 'output') {
            continue;
          }
          final bits = (portEntry.value as List).cast<Object>();
          final newBits = [
            for (final b in bits) b is int ? (arrayConcatOldToNew[b] ?? b) : b,
          ];
          if (bits.indexed.any((e) => e.$2 != newBits[e.$1])) {
            conns[portEntry.key] = newBits;
          }
        }
      }
    }

    // -- Netnames --------------------------------------------------------
    final netnames = <String, Object?>{};
    final emittedNames = <String>{};

    // InlineSystemVerilog modules are pure combinational — all their
    // signals are derivable from the gate netlist.
    final isInlineSV = module is InlineSystemVerilog;

    void addNetname(String name, List<Object> bits,
        {bool hideName = false, bool computed = false}) {
      if (emittedNames.contains(name)) {
        return;
      }
      emittedNames.add(name);
      netnames[name] = {
        'bits': bits,
        if (hideName) 'hide_name': 1,
        'attributes': <String, Object?>{
          if (computed || isInlineSV) 'computed': 1,
        },
      };
    }

    // Port nets (already aliased above).
    for (final p in ports.entries) {
      addNetname(Sanitizer.sanitizeSV(p.key),
          (p.value['bits']! as List).cast<Object>());
    }

    // Named signals from SynthModuleDefinition.
    if (synthDef != null) {
      for (final entry in synthLogicIds.entries
          .where((e) => !e.key.isConstant && !e.key.declarationCleared)) {
        final sl = entry.key;
        final name = tryGetSynthLogicName(sl);
        if (name != null) {
          var bits = applyAlias(entry.value.cast<Object>());
          // For element signals whose IDs were remapped by the
          // array_concat fresh-ID pass, apply that mapping so the
          // element netname matches the concat input (fresh) IDs.
          if (arrayConcatOldToNew.isNotEmpty && sl is SynthLogicArrayElement) {
            bits = bits
                .map((b) => b is int ? (arrayConcatOldToNew[b] ?? b) : b)
                .toList();
          }
          addNetname(Sanitizer.sanitizeSV(name), bits);
        }
      }
    }

    // Constant netnames for non-blocked constants (already aliased via
    // cell connections above).
    for (final cellEntry
        in cells.entries.where((e) => e.value['type'] == r'$const')) {
      final conns =
          cellEntry.value['connections'] as Map<String, List<Object>>?;
      if (conns != null && conns.isNotEmpty) {
        addNetname(cellEntry.key, conns.values.first, computed: true);
      }
    }

    // -- Ensure every bit ID in cell connections has a netname ------------
    {
      final coveredIds = netnames.values
          .expand(
              (nn) => ((nn! as Map<String, Object?>)['bits'] as List?) ?? [])
          .whereType<int>()
          .toSet();

      for (final cellEntry in cells.entries) {
        final cellName = cellEntry.key;
        final conns =
            cellEntry.value['connections'] as Map<String, dynamic>? ?? {};
        for (final connEntry in conns.entries) {
          final portName = connEntry.key;
          final bits = connEntry.value as List;
          final missingBits = <Object>[];
          for (final b in bits) {
            if (b is int && !coveredIds.contains(b)) {
              missingBits.add(b);
              coveredIds.add(b);
            }
          }
          if (missingBits.isNotEmpty) {
            addNetname(
                Sanitizer.sanitizeSV('${cellName}_$portName'), missingBits,
                hideName: true);
          }
        }
      }
    }

    // -- Slim: strip cell connections ------------------------------------
    // The full pipeline ran identically, so the cell set (keys, ordering)
    // is canonical.  Now drop the connection maps to reduce the output
    // size.  This is the ONLY difference between slim and full output.
    if (options.slimMode) {
      for (final cell in cells.values) {
        cell.remove('connections');
      }
    }

    return NetlistSynthesisResult(
      module,
      getInstanceTypeOfModule,
      ports: ports,
      cells: cells,
      netnames: netnames,
      attributes: attr,
    );
  }

  /// Apply all post-processing passes to the modules map.
  ///
  /// This is the canonical pass ordering used by both netlist flows:
  /// **Flow 1** (slim batch via `_synthesizeSlimModules`) and
  /// **Flow 2** (incremental full via `moduleNetlistJson`).
  /// Also used internally by [buildModulesMap] / [synthesizeToJson].
  void applyPostProcessingPasses(
    Map<String, Map<String, Object?>> modules,
  ) {
    if (options.groupStructConversions) {
      if (options.groupMaximalSubsets) {
        applyMaximalSubsetGrouping(modules);
      }
      if (options.collapseConcats) {
        applyCollapseConcats(modules);
      }
      if (options.collapseSelectsIntoPack) {
        applyCollapseSelectsIntoPack(modules);
      }
      if (options.collapseUnpackToConcat) {
        applyCollapseUnpackToConcat(modules);
      }
      if (options.collapseUnpackToPack) {
        applyCollapseUnpackToPack(modules);
      }
      applyStructConversionGrouping(modules);
      if (options.collapseStructGroups) {
        collapseStructGroupModules(modules);
      }
      applyStructBufferInsertion(modules);
      applyConcatToBufferReplacement(modules);
    }
  }

  /// Build the processed modules map from a [SynthBuilder]'s results.
  ///
  /// Returns the intermediate module map (definition name → module data)
  /// after all post-processing passes have been applied.  This allows
  /// callers to retain per-module results for incremental serving while
  /// avoiding redundant re-synthesis.
  Future<Map<String, Map<String, Object?>>> buildModulesMap(
      SynthBuilder synth, Module top) async {
    final modules =
        collectModuleEntries(synth.synthesisResults, topModule: top);

    applyPostProcessingPasses(modules);

    return modules;
  }

  /// Generate the combined netlist JSON from a [SynthBuilder]'s results.
  Future<String> generateCombinedJson(SynthBuilder synth, Module top) async {
    final modules = await buildModulesMap(synth, top);

    if (options.compressBitRanges) {
      compressModulesMap(modules);
    }

    final combined = {
      'creator': 'NetlistSynthesizer (rohd)',
      'modules': modules,
    };

    final encoder = options.compactJson
        ? const JsonEncoder()
        : const JsonEncoder.withIndent('  ');
    return encoder.convert(combined);
  }

  /// Convenience: synthesize [top] into a combined netlist JSON string.
  ///
  /// Builds a [SynthBuilder] internally and returns the full JSON.
  Future<String> synthesizeToJson(Module top) async {
    final sb = SynthBuilder(top, this);
    return generateCombinedJson(sb, top);
  }
}

/// A version of [BusSubset] that creates explicit `$slice` cells for
/// [LogicArray] element extraction in the netlist.
///
/// When a [LogicArray] port is decomposed into its elements, each element
/// gets its own [_BusSubsetForArraySlice] so the netlist shows explicit
/// select gates rather than flat bit aliasing.
class _BusSubsetForArraySlice extends BusSubset {
  _BusSubsetForArraySlice(
    super.bus,
    super.startIndex,
    super.endIndex,
  ) : super(name: 'array_slice');

  @override
  bool get hasBuilt => true;
}

/// A version of [Swizzle] that creates explicit `$concat` cells for
/// [LogicArray] element assembly in the netlist.
///
/// When a [LogicArray]'s elements are driven independently (e.g. by
/// constants), this creates a visible concat gate in the netlist that
/// assembles the element signals into the full packed array bus.
class _SwizzleForArrayConcat extends Swizzle {
  _SwizzleForArrayConcat(super.signals) : super(name: 'array_concat');

  @override
  bool get hasBuilt => true;
}
