// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synthesizer.dart
// A netlist synthesizer built on [SynthModuleDefinition].
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_cell.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_cell_mapper.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_module_translation.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_passes.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_port_direction.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_synthesis_result.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_utils.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_validation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

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
/// const configuration = NetlistSynthesizerConfiguration(
///   collapseTransparentClusters: true,
/// );
/// final synth = NetlistSynthesizer(configuration: configuration);
/// final builder = SynthBuilder(topModule, synth);
/// final json = synth.synthesizeToJson(topModule);
/// ```
class NetlistSynthesizer extends Synthesizer {
  /// The version of the ROHD extensions to the Yosys JSON netlist format.
  ///
  /// Consumers of ROHD-generated netlists must reject an unsupported version.
  /// This version changes when ROHD adds or changes fields that affect how a
  /// consumer interprets the netlist.
  static const String formatVersion = '0.0.1';

  /// The configuration controlling netlist synthesis.
  ///
  /// See [NetlistSynthesizerConfiguration] for documentation on individual
  /// fields.
  final NetlistSynthesizerConfiguration configuration;

  final SynthModuleStopPolicy _moduleStopPolicy;

  final NetlistCellMapper _netlistCellMapper;

  /// The hierarchy stopping policy used by this synthesizer.
  SynthModuleStopPolicy get moduleStopPolicy => _moduleStopPolicy;

  /// Convenience accessor for the netlist-cell mapper.
  @visibleForTesting
  NetlistCellMapper get netlistCellMapper => _netlistCellMapper;

  /// Creates a [NetlistSynthesizer].
  ///
  /// All synthesis parameters are bundled in [configuration]; see
  /// [NetlistSynthesizerConfiguration] for documentation on each field.
  NetlistSynthesizer({
    this.configuration = const NetlistSynthesizerConfiguration(),
  })  : _moduleStopPolicy = configuration.moduleStopPolicy ??
            SynthModuleStopPolicy.netlist(
                leafModulePredicate: configuration.leafModulePredicate),
        _netlistCellMapper =
            configuration.netlistCellMapper ?? NetlistCellMapper.withDefaults();

  @override
  bool generatesDefinition(Module module) =>
      moduleStopPolicy.generatesDefinition(module);

  @override
  SynthesisResult synthesize(
    Module module,
    String Function(Module module) getInstanceTypeOfModule, {
    SynthesisResult? Function(Module module)? lookupExistingResult,
    Map<Module, SynthesisResult>? existingResults,
  }) {
    final attr = <String, Object?>{'src': 'generated'};

    final translation = NetlistModuleTranslation(module,
        netlistCellMapper: netlistCellMapper,
        generatesDefinition: generatesDefinition,
        getInstanceTypeOfModule: getInstanceTypeOfModule)
      ..processPorts()
      ..processInternalWires()
      ..processCells();
    final synthDef = translation.synthDef;
    final ports = translation.ports;
    final cells = translation.cells;
    final getIds = translation.getIds;

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
      List<int> elemIds,
      int offset,
      int width,
      Logic elemLogic,
      Logic parentLogic,
      List<int> fullParentIds
    })>[];

    // Pending $struct_pack fields: for output struct ports, instead of
    // aliasing port bits to leaf bits (which causes "shorting"), we
    // collect structure-pack field operations and emit explicit cells later.
    // Each entry records: field (src) → port sub-range [lower:upper].
    final structPackFields = <({
      List<int> srcIds,
      List<int> dstIds,
      int dstLowerIndex,
      int dstUpperIndex,
      SynthLogic srcSynthLogic,
      SynthLogic dstSynthLogic
    })>[];

    // Track struct ports (both output ports of the current module AND
    // sub-module input struct ports) so Step 3 can skip $struct_field
    // collection for them ($struct_pack handles these instead).
    final outputStructPortLogics = <Logic>{};

    if (synthDef != null) {
      // 1. Non-partial assignments: src drives dst → dst IDs become
      //    src IDs (the driver's IDs are canonical).
      void aliasArrayChildren(SynthLogic src, SynthLogic dst) {
        final srcLogic = src.logics.firstOrNull;
        final dstLogic = dst.logics.firstOrNull;
        if (srcLogic is! LogicArray || dstLogic is! LogicArray) {
          return;
        }
        if (srcLogic.elements.length != dstLogic.elements.length) {
          return;
        }

        for (final (index, srcElement) in srcLogic.elements.indexed) {
          final dstElement = dstLogic.elements[index];
          final srcElementSynth = synthDef.logicToSynthMap[srcElement];
          final dstElementSynth = synthDef.logicToSynthMap[dstElement];
          if (srcElementSynth == null || dstElementSynth == null) {
            continue;
          }

          final srcElementLogic = srcElementSynth.logics.firstOrNull;
          final dstElementLogic = dstElementSynth.logics.firstOrNull;
          if (srcElementLogic is LogicArray && dstElementLogic is LogicArray) {
            aliasArrayChildren(srcElementSynth, dstElementSynth);
          }

          final srcElementIds = getIds(srcElementSynth);
          final dstElementIds = getIds(dstElementSynth);
          final len = srcElementIds.length < dstElementIds.length
              ? srcElementIds.length
              : dstElementIds.length;
          for (var i = 0; i < len; i++) {
            if (dstElementIds[i] != srcElementIds[i]) {
              idAlias[dstElementIds[i]] = srcElementIds[i];
            }
          }
        }
      }

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
        aliasArrayChildren(assignment.src, assignment.dst);
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
          structPackFields.add((
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
      //    SynthArraySlice / SynthArrayConcat), aliasing
      //    is skipped entirely — the cells provide the structural link.
      //
      //    Applied to ALL instances (ports AND internal signals) since
      //    internal arrays/structs (e.g. constant-driven coefficients)
      //    also need child→parent aliasing.
      //
      //    - LogicStructure (non-array): walks leafElements (recursive)
      //    - LogicArray: walks elements (direct children only, since
      //      each element is already a flat bitvector).
      //      For input array ports that have SynthArraySlice
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
        if (inst.module is SynthArraySlice) {
          // The input of the BusSubset is the array port.
          for (final inputSL in inst.inputMapping.values) {
            final logic = synthDef.logicToSynthMap.entries
                .where(
                  (e) => e.value == inputSL || e.value.replacement == inputSL,
                )
                .map((e) => e.key)
                .firstOrNull;
            if (logic != null && logic is LogicArray) {
              arraysWithExplicitCells.add(logic);
            }
            // Also check the resolved replacement chain.
            final resolved = inputSL.resolved;
            final logic2 = synthDef.logicToSynthMap.entries
                .where((e) => e.value == resolved)
                .map((e) => e.key)
                .firstOrNull;
            if (logic2 != null && logic2 is LogicArray) {
              arraysWithExplicitCells.add(logic2);
            }
          }
        }
        if (inst.module is SynthArrayConcat) {
          // The output of the Swizzle is the array signal.
          for (final outputSL in inst.outputMapping.values) {
            final logic = synthDef.logicToSynthMap.entries
                .where(
                  (e) => e.value == outputSL || e.value.replacement == outputSL,
                )
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
          // handled by $struct_pack cells (from Step 2).
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
                  elemIds: elemIds.sublist(0, sliceLen),
                  offset: idx,
                  width: sliceLen,
                  elemLogic: elem,
                  parentLogic: logic,
                  fullParentIds: parentIds,
                ));
              }
            } else if (elem is LogicStructure && elem is! LogicArray) {
              // Nested InterfaceStructure: the intermediate struct
              // itself has no SynthLogic, but its leaf elements do
              // (created by _subsetReceiveStructPort).  Walk leaf
              // elements and emit struct field entries for each,
              // using the top-level parent as the parent Logic.
              var leafIdx = idx;
              for (final leaf in elem.leafElements) {
                final leafSL = synthDef.logicToSynthMap[leaf];
                if (leafSL != null) {
                  final leafIds = getIds(leafSL);
                  final sliceLen = leafIds.length < parentIds.length - leafIdx
                      ? leafIds.length
                      : parentIds.length - leafIdx;
                  if (sliceLen > 0) {
                    structFieldCells.add((
                      elemIds: leafIds.sublist(0, sliceLen),
                      offset: leafIdx,
                      width: sliceLen,
                      elemLogic: leaf,
                      parentLogic: logic,
                      fullParentIds: parentIds,
                    ));
                  }
                }
                leafIdx += leaf.width;
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
    List<Object> applyAlias(List<Object> bits) => idAlias.isEmpty
        ? bits
        : bits.map((b) => b is int ? resolveAlias(b) : b).toList();

    // -- Break shared wire IDs for array slice/concat cells -----------------
    // (Populated inside the alias block below; declared here so netnames
    // can reference it later.)
    final arraySliceOldToNew = <int, int>{};

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

      // After aliasing, the slice output Y bits share the same wire IDs
      // as the corresponding sub-range of input A (because LogicArray
      // elements share the parent's bit storage).  This makes the slice
      // trivial and it would be elided below.
      //
      // To preserve the structural decomposition in the schematic, we
      // allocate fresh wire IDs for each array_slice Y output, then
      // redirect all other cells that consume those IDs as inputs to
      // read from the fresh IDs instead.  The slice input A keeps the
      // original parent-array IDs, so the data flow becomes:
      //   parent (original IDs) → slice A → slice Y (fresh IDs) → consumer

      for (final cellEntry in cells.entries) {
        // Only array slices need fresh outputs; other cells retain their
        // aliased connections until downstream inputs are rewritten below.
        if (!NetlistCell.hasOrigin(
          cellEntry.value,
          NetlistCellOrigin.arraySlice,
        )) {
          continue;
        }
        final cell = cellEntry.value as Map<String, dynamic>;
        final conns = cell['connections'] as Map<String, dynamic>;
        final dirs = cell['port_directions'] as Map<String, dynamic>;

        for (final portEntry in conns.entries.toList()) {
          if (dirs[portEntry.key] != 'output') {
            continue;
          }
          final oldBits = (portEntry.value as List).cast<Object>();
          conns[portEntry.key] = [
            for (final b in oldBits)
              if (b is int)
                arraySliceOldToNew.putIfAbsent(
                  b,
                  translation.allocateWireId,
                )
              else
                b,
          ];
        }
      }

      // Redirect other cells: any input port bit that matches an old ID
      // gets replaced with the corresponding fresh ID.
      if (arraySliceOldToNew.isNotEmpty) {
        for (final cellEntry in cells.entries) {
          if (NetlistCell.hasOrigin(
            cellEntry.value,
            NetlistCellOrigin.arraySlice,
          )) {
            // Keep each slice input connected to the original parent-array
            // bits. Rewriting it would bypass the slice by connecting both
            // its input and fresh output to the replacement IDs.
            continue;
          }
          final cell = cellEntry.value as Map<String, dynamic>;
          final conns = cell['connections'] as Map<String, dynamic>;
          final dirs = cell['port_directions'] as Map<String, dynamic>;

          for (final portEntry in conns.entries.toList()) {
            if (dirs[portEntry.key] != 'input') {
              continue;
            }
            final bits = (portEntry.value as List).cast<Object>();
            final newBits = [
              for (final b in bits)
                if (b is int) arraySliceOldToNew[b] ?? b else b,
            ];
            if (bits.indexed.any((e) => e.$2 != newBits[e.$1])) {
              conns[portEntry.key] = newBits;
            }
          }
        }
      }
    }

    // -- Elide trivial $slice cells ----------------------------------
    // Also elide struct_slice cells ([SynthStructureSlice] instances from
    // `_subsetReceiveStructPort`) because the new `$struct_unpack` cells
    // emitted below supersede them with better-named field-level connections.
    cells.removeWhere((cellKey, cell) {
      if (cell['type'] != r'$slice') {
        return false;
      }
      // Unconditionally remove struct_slice cells — they are duplicated by
      // $struct_unpack cells which carry field names.
      if (NetlistCell.hasOrigin(cell, NetlistCellOrigin.structureSlice)) {
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
      return yBits.indexed.every(
        (e) => offset + e.$1 < aBits.length && e.$2 == aBits[offset + e.$1],
      );
    });

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
                List<int> elemIds,
                int offset,
                int width,
                Logic elemLogic,
                Logic parentLogic,
                List<int> fullParentIds
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
                elemLogic: sf.elemLogic
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

        final structLayout = parentLogic is LogicStructure
            ? SynthStructureLayout(parentLogic)
            : null;

        // Build port_directions and connections with one output per field.
        final portDirs = <String, NetlistPortDirection>{
          'A': NetlistPortDirection.input,
        };
        final conns = <String, List<Object>>{'A': resolvedParentBits};

        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          final fieldName = structLayout?.fieldNameAt(f.offset,
                  fallbackName: f.elemLogic.name, anonymousUnpreferred: true) ??
              f.elemLogic.name;
          // Disambiguate duplicate field names with index suffix.
          var portName = fieldName;
          if (portDirs.containsKey(portName)) {
            portName = '${fieldName}_$i';
          }
          portDirs[portName] = NetlistPortDirection.output;
          conns[portName] = f.resolvedElemBits;
        }

        // Parameters list field metadata for the schematic viewer.
        final params = <String, Object?>{
          'STRUCT_NAME': parentLogic.name,
          'FIELD_COUNT': nonTrivialFields.length,
        };
        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          params['FIELD_${i}_NAME'] = structLayout?.fieldNameAt(f.offset,
                  fallbackName: f.elemLogic.name, anonymousUnpreferred: true) ??
              f.elemLogic.name;
          params['FIELD_${i}_OFFSET'] = f.offset;
          params['FIELD_${i}_WIDTH'] = f.width;
        }

        cells['struct_unpack_${suIdx}_$structName'] = NetlistCell(
          type: r'$struct_unpack',
          origin: NetlistCellOrigin.structureUnpack,
          parameters: params,
          portDirections: portDirs,
          connections: conns,
        ).toJson();
        suIdx++;
      }
    }

    // -- Emit $struct_pack cells for output struct ports ------------------
    // Group compose entries by destination port and emit a single
    // multi-port cell per group.  Each group has:
    //   • one input port per non-trivial field
    //   • output port Y: the full packed output bus
    // This emits explicit structure packing cells.
    if (structPackFields.isNotEmpty) {
      // Group by destination SynthLogic identity.
      final packGroups = <SynthLogic,
          List<
              ({
                List<int> srcIds,
                List<int> dstIds,
                int dstLowerIndex,
                int dstUpperIndex,
                SynthLogic srcSynthLogic,
                SynthLogic dstSynthLogic,
              })>>{};
      for (final sc in structPackFields) {
        (packGroups[sc.dstSynthLogic] ??= []).add(sc);
      }

      for (final entry in packGroups.entries) {
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
                srcSynthLogic: sc.srcSynthLogic
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

        // Derive struct metadata from the destination Logic.
        final dstLogic = dstSynthLogic.logics.firstOrNull;
        final structName =
            dstLogic != null ? Sanitizer.sanitizeSV(dstLogic.name) : 'struct';
        final structLayout =
            dstLogic is LogicStructure ? SynthStructureLayout(dstLogic) : null;
        final cellName = dstLogic != null
            ? NetlistUtils.synthesizedCellName(
                operationName: SynthStructureConcat.operationName,
                destination: dstLogic,
              )
            : SynthStructureConcat.operationName;

        // Build port_directions and connections.
        final portDirs = <String, NetlistPortDirection>{};
        final conns = <String, List<Object>>{};

        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          final fieldName = structLayout?.fieldNameAt(f.dstLowerIndex,
                  fallbackName: f.srcSynthLogic.resolved.name) ??
              f.srcSynthLogic.resolved.name;
          var portName = fieldName;
          if (portDirs.containsKey(portName)) {
            portName = '${fieldName}_$i';
          }
          portDirs[portName] = NetlistPortDirection.input;
          conns[portName] = f.resolvedSrcBits;
        }

        // Output port Y: full destination bus.
        portDirs['Y'] = NetlistPortDirection.output;
        conns['Y'] = resolvedDstBits;

        // Parameters list field metadata for the schematic viewer.
        final params = <String, Object?>{
          'STRUCT_NAME': dstLogic?.name ?? 'struct',
          'FIELD_COUNT': nonTrivialFields.length,
        };
        for (var i = 0; i < nonTrivialFields.length; i++) {
          final f = nonTrivialFields[i];
          params['FIELD_${i}_NAME'] = structLayout?.fieldNameAt(f.dstLowerIndex,
                  fallbackName: f.srcSynthLogic.resolved.name) ??
              f.srcSynthLogic.resolved.name;
          params['FIELD_${i}_OFFSET'] = f.dstLowerIndex;
          params['FIELD_${i}_WIDTH'] = f.dstUpperIndex - f.dstLowerIndex + 1;
        }

        cells['${cellName}_$structName'] = NetlistCell(
          type: r'$struct_pack',
          origin: NetlistCellOrigin.structurePack,
          parameters: params,
          portDirections: portDirs,
          connections: conns,
        ).toJson();
      }
    }

    final preservedNameBits = translation.preservedNameBits(applyAlias);
    translation
      ..processCellCleanup(
        enableDce: configuration.enableDeadCellElimination,
        preservedNameBits: preservedNameBits,
      )
      ..processConstants(
        applyAlias: applyAlias,
        pruneFloating: configuration.enableDeadCellElimination,
        preservedNameBits: preservedNameBits,
      );

    // -- Break shared wire IDs for array_concat cells --------------------
    // After aliasing, concat Y can share wire IDs with the independently
    // driven element inputs (because LogicArray elements share the parent's
    // bit storage).  This makes concat Y a second driver of the element wires.
    //
    // Allocate fresh IDs for concat Y and redirect downstream consumers to
    // those fresh IDs. The concat inputs keep the original element IDs, so
    // data flow is:
    //   element drivers → concat input → concat Y (fresh IDs) → consumer
    final arrayConcatOldToNew = <int, int>{};
    final arrayConcatReplacements =
        <({String cellKey, List<Object> oldBits, List<Object> newBits})>[];
    final outputPortBitSets = [
      for (final port in ports.values)
        if ((port as Map<String, dynamic>)['direction'] == 'output')
          (port['bits'] as List).whereType<int>().toSet(),
    ];

    for (final cellEntry in cells.entries) {
      if (!NetlistCell.hasOrigin(
        cellEntry.value,
        NetlistCellOrigin.arrayConcat,
      )) {
        continue;
      }
      final cell = cellEntry.value as Map<String, dynamic>;
      final conns = cell['connections'] as Map<String, dynamic>;
      final dirs = cell['port_directions'] as Map<String, dynamic>;

      for (final portEntry in conns.entries.toList()) {
        if (dirs[portEntry.key] != 'output') {
          continue;
        }
        final oldBits = (portEntry.value as List).cast<Object>();
        final oldBitSet = oldBits.whereType<int>().toSet();
        if (outputPortBitSets.any((outputBits) =>
            outputBits.length == oldBitSet.length &&
            outputBits.containsAll(oldBitSet))) {
          continue;
        }
        final newBits = [
          for (final b in oldBits)
            if (b is int) translation.allocateWireId() else b,
        ];
        conns[portEntry.key] = newBits;
        arrayConcatReplacements
            .add((cellKey: cellEntry.key, oldBits: oldBits, newBits: newBits));
      }
    }

    final arrayConcatOutputProducers = <int, List<int>>{};
    for (final (index, replacement) in arrayConcatReplacements.indexed) {
      for (final bit in replacement.oldBits) {
        if (bit is int) {
          (arrayConcatOutputProducers[bit] ??= []).add(index);
        }
      }
    }

    List<Object> rewriteArrayConcatConsumerBits(
      List<Object> bits, {
      String? consumingCellKey,
    }) {
      for (final replacement in arrayConcatReplacements) {
        if (replacement.cellKey == consumingCellKey ||
            replacement.oldBits.length != bits.length) {
          continue;
        }
        if (bits.indexed
            .every((entry) => entry.$2 == replacement.oldBits[entry.$1])) {
          return replacement.newBits;
        }
      }

      final newBits = <Object>[];
      var changed = false;
      for (final bit in bits) {
        if (bit is! int) {
          newBits.add(bit);
          continue;
        }
        final producerIndices = arrayConcatOutputProducers[bit]
            ?.where((index) =>
                arrayConcatReplacements[index].cellKey != consumingCellKey)
            .toList();
        if (producerIndices == null || producerIndices.length != 1) {
          newBits.add(bit);
          continue;
        }
        final producer = arrayConcatReplacements[producerIndices.single];
        final bitIndex = producer.oldBits.indexOf(bit);
        if (bitIndex < 0) {
          newBits.add(bit);
          continue;
        }
        newBits.add(producer.newBits[bitIndex]);
        changed = true;
      }
      return changed ? newBits : bits;
    }

    // Redirect downstream consumers: any input port or module output bit that
    // matches an old concat Y ID gets replaced with the corresponding fresh ID.
    if (arrayConcatReplacements.isNotEmpty) {
      for (final portEntry in ports.values) {
        final port = portEntry as Map<String, dynamic>;
        if (port['direction'] != 'output') {
          continue;
        }
        final bits = (port['bits'] as List).cast<Object>();
        final newBits = rewriteArrayConcatConsumerBits(bits);
        if (bits.indexed.any((e) => e.$2 != newBits[e.$1])) {
          port['bits'] = newBits;
        }
      }

      for (final cellEntry in cells.entries) {
        final cell = cellEntry.value as Map<String, dynamic>;
        final conns = cell['connections'] as Map<String, dynamic>;
        final dirs = cell['port_directions'] as Map<String, dynamic>;

        for (final portEntry in conns.entries.toList()) {
          if (dirs[portEntry.key] != 'input') {
            continue;
          }
          final bits = (portEntry.value as List).cast<Object>();
          final newBits = rewriteArrayConcatConsumerBits(bits,
              consumingCellKey: cellEntry.key);
          if (bits.indexed.any((e) => e.$2 != newBits[e.$1])) {
            conns[portEntry.key] = newBits;
          }
        }
      }
    }

    translation.processNetnames(
        applyAlias: applyAlias,
        arraySliceOldToNew: arraySliceOldToNew,
        arrayConcatOldToNew: arrayConcatOldToNew,
        pruneUndriven: configuration.enableDeadCellElimination,
        drivenBits: configuration.enableDeadCellElimination
            ? NetlistValidation.connectedBits(ports, cells,
                portDirections: const {'input', 'inout'},
                cellDirection: 'output')
            : const {});
    final netnames = translation.netnames;

    // -- Structural validation -------------------------------------------
    NetlistValidation.validate(ports, cells, module.name, netnames: netnames);

    return NetlistSynthesisResult(module, getInstanceTypeOfModule,
        ports: ports, cells: cells, netnames: netnames, attributes: attr);
  }

  /// Apply all post-processing passes to the modules map.
  ///
  /// This is the canonical pass ordering used by both the slim and full JSON
  /// projections produced by [buildModulesMap] and [synthesizeToJson].
  void applyPostProcessingPasses(Map<String, Map<String, Object?>> modules) {
    if (configuration.collapseTransparentClusters) {
      NetlistPasses.collapseConcatOfAdjacentSlices(modules);
      NetlistPasses.removeTrivialConcatAliases(modules);
      NetlistPasses.applyTransparentClustering(modules);
      NetlistPasses.removeUnconsumedTransparentCells(modules);
    }
  }

  /// Build the processed modules map from a [SynthBuilder]'s results.
  ///
  /// Returns the intermediate module map (definition name → module data)
  /// after all post-processing passes have been applied.  This allows
  /// callers to retain per-module results for incremental serving while
  /// avoiding redundant re-synthesis. [slimMode] overrides the configured
  /// default for this projection without modifying the retained results.
  Map<String, Map<String, Object?>> buildModulesMap(
      SynthBuilder synth, Module top,
      {bool? slimMode}) {
    final effectiveSlimMode = slimMode ?? configuration.slimMode;
    final swEntries = Stopwatch()..start();
    final modules = NetlistPasses.collectModuleEntries(synth.synthesisResults,
        topModule: top, includeCellConnections: !effectiveSlimMode);
    swEntries.stop();

    final swPasses = Stopwatch()..start();
    applyPostProcessingPasses(modules);
    swPasses.stop();

    return modules;
  }

  /// Generate the combined netlist JSON from a [SynthBuilder]'s results.
  String generateCombinedJson(SynthBuilder synth, Module top,
      {bool? slimMode}) {
    final swCollect = Stopwatch()..start();
    final modules = buildModulesMap(synth, top, slimMode: slimMode);
    swCollect.stop();

    final swCompress = Stopwatch()..start();
    if (configuration.compressBitRanges) {
      _compressModulesMap(modules);
    }
    swCompress.stop();

    final combined = {
      'creator': 'NetlistSynthesizer (rohd)',
      'version': formatVersion,
      'modules': modules
    };

    final swEncode = Stopwatch()..start();
    final encoder = configuration.compactJson
        ? const JsonEncoder()
        : const JsonEncoder.withIndent('  ');
    final result = encoder.convert(combined);
    swEncode.stop();

    return result;
  }

  /// Compresses a list of bit IDs by replacing contiguous ascending runs of
  /// 3 or more integers with `"start:end"` range strings.
  static List<Object> _compressBits(List<Object> bits) {
    final result = <Object>[];
    final pending = <int>[];

    void flushPending() {
      if (pending.isEmpty) {
        return;
      }
      var i = 0;
      while (i < pending.length) {
        var j = i;
        while (j + 1 < pending.length && pending[j + 1] == pending[j] + 1) {
          j++;
        }
        final runLen = j - i + 1;
        if (runLen >= 3) {
          result.add('${pending[i]}:${pending[j]}');
        } else {
          for (var k = i; k <= j; k++) {
            result.add(pending[k]);
          }
        }
        i = j + 1;
      }
      pending.clear();
    }

    for (final element in bits) {
      if (element is int) {
        pending.add(element);
      } else {
        flushPending();
        result.add(element);
      }
    }
    flushPending();
    return result;
  }

  /// Applies [_compressBits] to all `bits` arrays and cell `connections`
  /// arrays in a modules map.
  static void _compressModulesMap(Map<String, Map<String, Object?>> modules) {
    for (final moduleDef in modules.values) {
      final ports = moduleDef['ports'] as Map<String, Map<String, Object?>>?;
      if (ports != null) {
        for (final port in ports.values) {
          final bits = port['bits'];
          if (bits is List) {
            port['bits'] = _compressBits(bits.cast<Object>());
          }
        }
      }

      final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
      if (cells != null) {
        for (final cell in cells.values) {
          final conns = cell['connections'] as Map<String, dynamic>?;
          if (conns != null) {
            for (final key in conns.keys.toList()) {
              conns[key] = _compressBits((conns[key] as List).cast<Object>());
            }
          }
        }
      }

      final netnames = moduleDef['netnames'] as Map<String, Object?>?;
      if (netnames != null) {
        for (final entry in netnames.values) {
          if (entry is Map<String, Object?>) {
            final bits = entry['bits'];
            if (bits is List) {
              entry['bits'] = _compressBits(bits.cast<Object>());
            }
          }
        }
      }
    }
  }

  /// Convenience: synthesize [top] into a combined netlist JSON string.
  ///
  /// Builds a [SynthBuilder] internally and returns the full JSON.
  ///
  /// The [packageRoot] parameter is accepted for API compatibility with
  /// downstream trace-enabled branches. [slimMode] overrides the configured
  /// output mode for this call, allowing expansion after a slim request.
  String synthesizeToJson(Module top, {String? packageRoot, bool? slimMode}) {
    final sb = SynthBuilder(top, this);
    return generateCombinedJson(sb, top, slimMode: slimMode);
  }
}
