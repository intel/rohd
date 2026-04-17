// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_passes.dart
// Post-processing optimization passes for netlist synthesis.
//
// These passes operate on the modules map (definition name → module data)
// produced by [NetlistSynthesizer.synthesize].  They simplify the netlist
// by grouping struct conversions, collapsing redundant cells, and inserting
// buffer cells for cleaner schematic rendering.
//
// 2025 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Collects a combined modules map from [SynthesisResult]s suitable for
/// JSON emission.
Map<String, Map<String, Object?>> collectModuleEntries(
  Iterable<SynthesisResult> results, {
  Module? topModule,
}) {
  final allModules = <String, Map<String, Object?>>{};
  for (final result in results) {
    if (result is NetlistSynthesisResult) {
      final typeName = result.instanceTypeName;
      final attrs = Map<String, Object?>.from(result.attributes);
      if (topModule != null && result.module == topModule) {
        attrs['top'] = 1;
      }
      allModules[typeName] = {
        'attributes': attrs,
        'ports': result.ports,
        'cells': result.cells,
        'netnames': result.netnames,
      };
    }
  }
  return allModules;
}

// -- Maximal-subset grouping -------------------------------------------

/// Finds `$concat` cells whose input bits all trace back through
/// `$buf`/`$slice` chains to a contiguous sub-range of a single source
/// bus.  Replaces the entire concat-tree (the concat itself plus the
/// intermediate `$buf` and `$slice` cells that exclusively serve it)
/// with a single `$slice` (or `$buf` when the sub-range covers the
/// full source width).
///
/// This pass runs *before* the connected-component grouping so that
/// the simplified cells can be picked up by the standard struct-assign
/// grouping and collapse passes.
void applyMaximalSubsetGrouping(
  Map<String, Map<String, Object?>> allModules,
) {
  for (final moduleDef in allModules.values) {
    final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
    if (cells == null || cells.isEmpty) {
      continue;
    }

    // Build wire-driver, wire-consumer, and bit-to-net maps.
    final (:wireDriverCell, :wireConsumerCells, :bitToNetInfo) =
        buildWireMaps(cells, moduleDef);

    final cellsToRemove = <String>{};
    final cellsToAdd = <String, Map<String, Object?>>{};
    var replIdx = 0;

    // Process each $concat cell.
    for (final concatEntry in cells.entries.toList()) {
      final concatName = concatEntry.key;
      final concatCell = concatEntry.value;
      if ((concatCell['type'] as String?) != r'$concat') {
        continue;
      }
      if (cellsToRemove.contains(concatName)) {
        continue;
      }

      final conns = concatCell['connections'] as Map<String, dynamic>? ?? {};

      // Gather the concat's input bits in LSB-first order.
      final inputBits = <int>[];
      if (conns.containsKey('A')) {
        // Standard 2-input concat: A (LSB), B (MSB).
        for (final b in conns['A'] as List) {
          if (b is int) {
            inputBits.add(b);
          }
        }
        for (final b in conns['B'] as List) {
          if (b is int) {
            inputBits.add(b);
          }
        }
      } else {
        // Multi-input concat: range-named ports [lo:hi].
        final rangePorts = <int, List<int>>{};
        for (final portName in conns.keys) {
          if (portName == 'Y') {
            continue;
          }
          final m = rangePortRe.firstMatch(portName);
          if (m != null) {
            final hi = int.parse(m.group(1)!);
            final lo = m.group(2) != null ? int.parse(m.group(2)!) : hi;
            rangePorts[lo] = [
              for (final b in conns[portName] as List)
                if (b is int) b,
            ];
          }
        }
        for (final k in rangePorts.keys.toList()..sort()) {
          inputBits.addAll(rangePorts[k]!);
        }
      }

      if (inputBits.isEmpty) {
        continue;
      }

      final outputBits = <int>[
        for (final b in conns['Y'] as List)
          if (b is int) b,
      ];

      // Trace each input bit backward through $buf and $slice cells
      // to find its ultimate source bit.  Record the chain of
      // intermediate cells visited.
      final sourceBits = <int>[];
      final intermediateCells = <String>{};
      var allFromOneBus = true;
      String? sourceBusNet;
      List<int>? sourceBusBits;

      for (final inputBit in inputBits) {
        final (traced, chain) = traceBackward(inputBit, wireDriverCell, cells);
        sourceBits.add(traced);
        intermediateCells.addAll(chain);

        // Identify which named bus this bit belongs to.
        final info = bitToNetInfo[traced];
        if (info == null) {
          allFromOneBus = false;
          break;
        }
        if (sourceBusNet == null) {
          sourceBusNet = info.$1;
          sourceBusBits = info.$2;
        } else if (sourceBusNet != info.$1) {
          allFromOneBus = false;
          break;
        }
      }

      if (!allFromOneBus || sourceBusNet == null || sourceBusBits == null) {
        continue;
      }

      // Verify the traced source bits form a contiguous sub-range
      // of the source bus.
      if (sourceBits.length != inputBits.length) {
        continue;
      }

      // Find each source bit's index within the source bus.
      final indices = <int>[];
      var contiguous = true;
      for (final sb in sourceBits) {
        final idx = sourceBusBits.indexOf(sb);
        if (idx < 0) {
          contiguous = false;
          break;
        }
        indices.add(idx);
      }
      if (!contiguous || indices.isEmpty) {
        continue;
      }

      // Check that indices are sequential (contiguous ascending).
      for (var i = 1; i < indices.length; i++) {
        if (indices[i] != indices[i - 1] + 1) {
          contiguous = false;
          break;
        }
      }
      if (!contiguous) {
        continue;
      }

      // Verify that every intermediate cell is used exclusively
      // by this concat chain (no fanout to other consumers).
      if (!isExclusiveChain(
        intermediates: intermediateCells,
        ownerCell: concatName,
        cells: cells,
        wireConsumerCells: wireConsumerCells,
        allowPortConsumers: true,
      )) {
        continue;
      }

      // Build the source bus bits list (the full bus from the module).
      // We need the A connection to be the full source bus.
      final sourceBusParentBits = sourceBusBits.cast<Object>().toList();

      final offset = indices.first;
      final yWidth = outputBits.length;
      final aWidth = sourceBusBits.length;

      // Mark intermediate cells and the concat for removal.
      cellsToRemove
        ..addAll(intermediateCells)
        ..add(concatName);

      if (yWidth == aWidth) {
        cellsToAdd['maxsub_buf_$replIdx'] =
            makeBufCell(aWidth, sourceBusParentBits, outputBits.cast<Object>());
      } else {
        cellsToAdd['maxsub_slice_$replIdx'] = makeSliceCell(offset, aWidth,
            yWidth, sourceBusParentBits, outputBits.cast<Object>());
      }
      replIdx++;
    }

    // Apply removals and additions.
    cellsToRemove.forEach(cells.remove);
    cells.addAll(cellsToAdd);
  }
}

// -- Partial concat collapsing -----------------------------------------

/// Scans every module in [allModules] for `$concat` cells where a
/// contiguous run of input ports (≥ 2) all trace back through
/// `$buf`/`$slice` chains to a contiguous sub-range of a single source
/// bus with exclusive fan-out.  Each such run is replaced by a single
/// `$slice` and the concat is rebuilt with fewer input ports.
///
/// If *all* ports of a concat qualify as a single run, the concat is
/// eliminated entirely and replaced with a `$slice` (or `$buf` for
/// full-width).
void applyCollapseConcats(
  Map<String, Map<String, Object?>> allModules,
) {
  for (final moduleDef in allModules.values) {
    final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
    if (cells == null || cells.isEmpty) {
      continue;
    }

    // --- Build wire-driver, wire-consumer, and bit-to-net maps -------
    final (:wireDriverCell, :wireConsumerCells, :bitToNetInfo) =
        buildWireMaps(cells, moduleDef);

    final cellsToRemove = <String>{};
    final cellsToAdd = <String, Map<String, Object?>>{};
    var replIdx = 0;

    // --- Process each $concat cell ------------------------------------
    for (final concatEntry in cells.entries.toList()) {
      final concatName = concatEntry.key;
      final concatCell = concatEntry.value;
      if ((concatCell['type'] as String?) != r'$concat') {
        continue;
      }
      if (cellsToRemove.contains(concatName)) {
        continue;
      }

      final conns = concatCell['connections'] as Map<String, dynamic>? ?? {};

      // Parse input ports into an ordered list.
      // Supports both range-named ports [hi:lo] and A/B form.
      final inputPorts = <(int lo, String portName, List<int> bits)>[];
      var hasRangePorts = false;
      for (final portName in conns.keys) {
        if (portName == 'Y') {
          continue;
        }
        final m = rangePortRe.firstMatch(portName);
        if (m != null) {
          hasRangePorts = true;
          final hi = int.parse(m.group(1)!);
          final lo = m.group(2) != null ? int.parse(m.group(2)!) : hi;
          inputPorts.add((
            lo,
            portName,
            [
              for (final b in conns[portName] as List)
                if (b is int) b,
            ],
          ));
        }
      }
      if (!hasRangePorts) {
        // A/B form: convert to ordered list.
        if (conns.containsKey('A') && conns.containsKey('B')) {
          final aBits = [
            for (final b in conns['A'] as List)
              if (b is int) b,
          ];
          final bBits = [
            for (final b in conns['B'] as List)
              if (b is int) b,
          ];
          inputPorts
            ..add((0, 'A', aBits))
            ..add((aBits.length, 'B', bBits));
        }
      }
      inputPorts.sort((a, b) => a.$1.compareTo(b.$1));

      if (inputPorts.length < 2) {
        continue;
      }

      // --- Trace each port's bits back to a source bus ----------------
      final portTraces = <({
        String? busName,
        List<int>? busBits,
        List<int> sourceIndices,
        Set<String> intermediates,
        bool valid,
      })>[];

      for (final (_, _, bits) in inputPorts) {
        final sourceIndices = <int>[];
        final intermediates = <String>{};
        String? busName;
        List<int>? busBits;
        var valid = true;

        for (final bit in bits) {
          final (traced, chain) = traceBackward(bit, wireDriverCell, cells);
          intermediates.addAll(chain);

          // Identify source net.
          final info = bitToNetInfo[traced];
          if (info == null) {
            valid = false;
            break;
          }
          if (busName == null) {
            busName = info.$1;
            busBits = info.$2;
          } else if (busName != info.$1) {
            valid = false;
            break;
          }
          final idx = busBits!.indexOf(traced);
          if (idx < 0) {
            valid = false;
            break;
          }
          sourceIndices.add(idx);
        }

        // Check contiguous within this port.
        if (valid && sourceIndices.length == bits.length) {
          for (var i = 1; i < sourceIndices.length; i++) {
            if (sourceIndices[i] != sourceIndices[i - 1] + 1) {
              valid = false;
              break;
            }
          }
        } else {
          valid = false;
        }

        portTraces.add((
          busName: busName,
          busBits: busBits,
          sourceIndices: sourceIndices,
          intermediates: intermediates,
          valid: valid,
        ));
      }

      // --- Find maximal runs of consecutive traceable ports -----------
      final runs = <(int startIdx, int endIdx)>[];
      var runStart = 0;
      while (runStart < inputPorts.length) {
        final t = portTraces[runStart];
        if (!t.valid || t.busName == null) {
          runStart++;
          continue;
        }
        var runEnd = runStart;
        while (runEnd + 1 < inputPorts.length) {
          final nextT = portTraces[runEnd + 1];
          if (!nextT.valid) {
            break;
          }
          if (nextT.busName != t.busName) {
            break;
          }
          // Check contiguity across port boundary.
          final curLast = portTraces[runEnd].sourceIndices.last;
          final nextFirst = nextT.sourceIndices.first;
          if (nextFirst != curLast + 1) {
            break;
          }
          runEnd++;
        }
        if (runEnd > runStart) {
          runs.add((runStart, runEnd));
        }
        runStart = runEnd + 1;
      }

      if (runs.isEmpty) {
        continue;
      }

      // --- Verify exclusivity of intermediate cells for each run ------
      final validRuns =
          <(int startIdx, int endIdx, Set<String> intermediates)>[];
      for (final (startIdx, endIdx) in runs) {
        final allIntermediates = <String>{};
        for (var i = startIdx; i <= endIdx; i++) {
          allIntermediates.addAll(portTraces[i].intermediates);
        }
        if (isExclusiveChain(
          intermediates: allIntermediates,
          ownerCell: concatName,
          cells: cells,
          wireConsumerCells: wireConsumerCells,
        )) {
          validRuns.add((startIdx, endIdx, allIntermediates));
        }
      }

      if (validRuns.isEmpty) {
        continue;
      }

      // --- Check whether ALL ports form a single valid run ------------
      final allCollapsed = validRuns.length == 1 &&
          validRuns.first.$1 == 0 &&
          validRuns.first.$2 == inputPorts.length - 1;

      // Remove exclusive intermediate cells for all valid runs.
      for (final (_, _, intermediates) in validRuns) {
        cellsToRemove.addAll(intermediates);
      }

      if (allCollapsed) {
        // Full collapse — replace concat with a single $slice or $buf.
        final t0 = portTraces.first;
        final srcOffset = t0.sourceIndices.first;
        final yWidth = (conns['Y'] as List).whereType<int>().length;
        final aWidth = t0.busBits!.length;
        final sourceBusParentBits = t0.busBits!.cast<Object>().toList();
        final outputBits = <Object>[
          for (final b in conns['Y'] as List)
            if (b is int) b,
        ];

        cellsToRemove.add(concatName);
        if (yWidth == aWidth) {
          cellsToAdd['collapse_buf_$replIdx'] =
              makeBufCell(aWidth, sourceBusParentBits, outputBits);
        } else {
          cellsToAdd['collapse_slice_$replIdx'] = makeSliceCell(
              srcOffset, aWidth, yWidth, sourceBusParentBits, outputBits);
        }
        replIdx++;
        continue;
      }

      // --- Partial collapse — rebuild concat with fewer ports ---------
      cellsToRemove.add(concatName);

      final newConns = <String, List<Object>>{};
      final newDirs = <String, String>{};
      var outBitOffset = 0;

      var portIdx = 0;
      while (portIdx < inputPorts.length) {
        // Check if this port starts a valid run.
        (int, int, Set<String>)? activeRun;
        for (final run in validRuns) {
          if (run.$1 == portIdx) {
            activeRun = run;
            break;
          }
        }

        if (activeRun != null) {
          final (startIdx, endIdx, _) = activeRun;
          // Compute combined width and collect original input wire bits.
          final originalBits = <Object>[];
          for (var i = startIdx; i <= endIdx; i++) {
            originalBits.addAll(inputPorts[i].$3.cast<Object>());
          }
          final width = originalBits.length;
          final t0 = portTraces[startIdx];
          final srcOffset = t0.sourceIndices.first;
          final sourceBusBits = t0.busBits!.cast<Object>().toList();

          // Reuse the original concat-input wire bits as the $slice
          // output so that existing netname associations are preserved.
          cellsToAdd['collapse_slice_$replIdx'] = makeSliceCell(srcOffset,
              t0.busBits!.length, width, sourceBusBits, originalBits);
          replIdx++;

          // Add the combined port to the rebuilt concat.
          final hi = outBitOffset + width - 1;
          final portName = hi == outBitOffset ? '[$hi]' : '[$hi:$outBitOffset]';
          newConns[portName] = originalBits;
          newDirs[portName] = 'input';
          outBitOffset += width;

          portIdx = endIdx + 1;
        } else {
          // Keep this port as-is.
          final port = inputPorts[portIdx];
          final width = port.$3.length;
          final hi = outBitOffset + width - 1;
          final portName = hi == outBitOffset ? '[$hi]' : '[$hi:$outBitOffset]';
          newConns[portName] = port.$3.cast<Object>();
          newDirs[portName] = 'input';
          outBitOffset += width;
          portIdx++;
        }
      }

      // Preserve Y.
      newConns['Y'] = [for (final b in conns['Y'] as List) b as Object];
      newDirs['Y'] = 'output';

      cellsToAdd['${concatName}_collapsed'] = {
        'hide_name': concatCell['hide_name'],
        'type': r'$concat',
        'parameters': <String, Object?>{},
        'attributes': concatCell['attributes'] ?? <String, Object?>{},
        'port_directions': newDirs,
        'connections': newConns,
      };
    }

    // Apply removals and additions.
    cellsToRemove.forEach(cells.remove);
    cells.addAll(cellsToAdd);
  }
}

// -- Struct-conversion grouping ----------------------------------------

/// Scans every module in [allModules] for connected components of `$slice`
/// and `$concat` cells that form reconvergent struct-conversion trees.
/// Such trees arise from `LogicStructure.gets()` when a flat bus is
/// assigned to a struct (or vice-versa): leaf fields are sliced out and
/// re-packed through potentially multiple levels of concats.
///
/// Each connected component is extracted into a new synthetic module
/// definition (added to [allModules]) and replaced in the parent with a
/// single hierarchical cell.  This collapses the visual noise in the
/// netlist into a tidy "struct_assign_*" box.
void applyStructConversionGrouping(
  Map<String, Map<String, Object?>> allModules,
) {
  // Collect new module definitions to add (avoid modifying map during
  // iteration).
  final newModuleDefs = <String, Map<String, Object?>>{};

  // Process each existing module definition.
  for (final moduleName in allModules.keys.toList()) {
    final moduleDef = allModules[moduleName]!;
    final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
    if (cells == null || cells.isEmpty) {
      continue;
    }

    // Identify all $slice and $concat cells.
    final sliceConcat = <String>{};
    for (final entry in cells.entries) {
      final type = entry.value['type'] as String?;
      if (type == r'$slice' || type == r'$concat') {
        sliceConcat.add(entry.key);
      }
    }
    if (sliceConcat.length < 2) {
      continue;
    }

    // Build wire-ID → driver cell and wire-ID → consumer cells maps.
    final (
      :wireDriverCell,
      wireConsumerCells: wireConsumerSets,
      :bitToNetInfo,
    ) = buildWireMaps(cells, moduleDef);
    // Convert Set<String> consumers to List<String> for iteration.
    final wireConsumerCells = <int, List<String>>{
      for (final e in wireConsumerSets.entries) e.key: e.value.toList(),
    };
    final modPorts = moduleDef['ports'] as Map<String, Map<String, Object?>>?;

    // Build adjacency among sliceConcat cells: two are adjacent if one's
    // output feeds the other's input.
    final adj = <String, Set<String>>{
      for (final cn in sliceConcat) cn: <String>{},
    };
    for (final cn in sliceConcat) {
      final cell = cells[cn]!;
      final conns = cell['connections'] as Map<String, dynamic>? ?? {};
      final pdirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
      for (final pe in conns.entries) {
        final d = pdirs[pe.key] as String? ?? '';
        for (final b in pe.value as List) {
          if (b is! int) {
            continue;
          }
          if (d == 'output') {
            // Find consumers in sliceConcat.
            for (final consumer in wireConsumerCells[b] ?? <String>[]) {
              if (consumer != cn && sliceConcat.contains(consumer)) {
                adj[cn]!.add(consumer);
                adj[consumer]!.add(cn);
              }
            }
          } else if (d == 'input') {
            // Find driver in sliceConcat.
            final drv = wireDriverCell[b];
            if (drv != null && drv != cn && sliceConcat.contains(drv)) {
              adj[cn]!.add(drv);
              adj[drv]!.add(cn);
            }
          }
        }
      }
    }

    // Find connected components via BFS.
    final visited = <String>{};
    final components = <Set<String>>[];
    for (final start in sliceConcat) {
      if (visited.contains(start)) {
        continue;
      }
      final comp = <String>{};
      final queue = [start];
      while (queue.isNotEmpty) {
        final node = queue.removeLast();
        if (!comp.add(node)) {
          continue;
        }
        visited.add(node);
        for (final nb in adj[node]!) {
          if (!comp.contains(nb)) {
            queue.add(nb);
          }
        }
      }
      if (comp.length >= 2) {
        components.add(comp);
      }
    }

    // For each connected component, extract it into a synthetic module.
    var groupIdx = 0;
    final groupQueue = [...components];
    var gqi = 0;
    final claimedCells = <String>{};
    while (gqi < groupQueue.length) {
      final comp = groupQueue[gqi++]..removeAll(claimedCells);
      if (comp.length < 2) {
        continue;
      }

      // Collect all wire IDs used inside the component and classify them
      // as internal-only (driven AND consumed within comp) or external
      // (boundary ports of the synthetic module).
      //
      // External inputs  = wire IDs consumed by comp cells but driven
      //                     outside the component.
      // External outputs = wire IDs produced by comp cells but consumed
      //                     outside the component (or by module ports).
      final compOutputIds = <int>{}; // driven by comp
      final compInputIds = <int>{}; // consumed by comp

      for (final cn in comp) {
        final cell = cells[cn]!;
        final conns = cell['connections'] as Map<String, dynamic>? ?? {};
        final pdirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
        for (final pe in conns.entries) {
          final d = pdirs[pe.key] as String? ?? '';
          for (final b in pe.value as List) {
            if (b is! int) {
              continue;
            }
            if (d == 'output') {
              compOutputIds.add(b);
            } else if (d == 'input') {
              compInputIds.add(b);
            }
          }
        }
      }

      // External input bits: consumed by comp but NOT driven by comp.
      final extInputBits = compInputIds.difference(compOutputIds);
      // External output bits: driven by comp but consumed outside comp
      // (by non-comp cells or by module output ports).
      final extOutputBits = <int>{};
      for (final b in compOutputIds) {
        // Check non-comp cell consumers.
        for (final consumer in wireConsumerCells[b] ?? <String>[]) {
          if (!comp.contains(consumer)) {
            extOutputBits.add(b);
            break;
          }
        }
        // Check module output ports.
        if (!extOutputBits.contains(b) && modPorts != null) {
          for (final portEntry in modPorts.values) {
            final dir = portEntry['direction'] as String?;
            if (dir != 'output') {
              continue;
            }
            final bits = portEntry['bits'] as List?;
            if (bits != null && bits.contains(b)) {
              extOutputBits.add(b);
              break;
            }
          }
        }
      }

      if (extInputBits.isEmpty || extOutputBits.isEmpty) {
        continue; // degenerate component, skip
      }

      // Group external bits by netname to form named ports.
      // Build a net-name → sorted bit IDs mapping for inputs and outputs.
      final netnames = moduleDef['netnames'] as Map<String, Object?>? ?? {};

      // Wire → netname map (for bits in this component).
      final wireToNet = <int, String>{};
      for (final nnEntry in netnames.entries) {
        final nd = nnEntry.value! as Map<String, Object?>;
        final bits = nd['bits'] as List? ?? [];
        for (final b in bits) {
          if (b is int) {
            wireToNet[b] = nnEntry.key;
          }
        }
      }

      // Group external input bits by their netname, preserving order.
      final inputGroups = <String, List<int>>{};
      for (final b in extInputBits) {
        final nn = wireToNet[b] ?? 'in_$b';
        (inputGroups[nn] ??= []).add(b);
      }
      for (final v in inputGroups.values) {
        v.sort();
      }

      // Group external output bits by their netname, preserving order.
      final outputGroups = <String, List<int>>{};
      for (final b in extOutputBits) {
        final nn = wireToNet[b] ?? 'out_$b';
        (outputGroups[nn] ??= []).add(b);
      }
      for (final v in outputGroups.values) {
        v.sort();
      }

      // Guard: only group when the component is a true struct
      // assignment — one signal split into selections then re-assembled
      // into one signal.  The input may be wider than the output when
      // fields are dropped (e.g. a nonCacheable bit unused in the
      // destination struct).  Multi-source concats (e.g. swizzles
      // combining independent signals) and simple bit-range selections
      // must remain as standalone cells.
      if (inputGroups.length != 1 ||
          outputGroups.length != 1 ||
          extInputBits.length < extOutputBits.length) {
        // Try sub-component extraction: for each $concat cell in the
        // component, backward-BFS to find the subset of cells that
        // transitively feed it.  If that subset is strictly smaller
        // than the full component it may pass the guard on its own.
        for (final cn in comp.toList()) {
          final cell = cells[cn];
          if (cell == null) {
            continue;
          }
          if ((cell['type'] as String?) != r'$concat') {
            continue;
          }

          final subComp = <String>{cn};
          final bfsQueue = <String>[cn];
          while (bfsQueue.isNotEmpty) {
            final cur = bfsQueue.removeLast();
            final curCell = cells[cur];
            if (curCell == null) {
              continue;
            }
            final cConns =
                curCell['connections'] as Map<String, dynamic>? ?? {};
            final cDirs =
                curCell['port_directions'] as Map<String, dynamic>? ?? {};
            for (final pe in cConns.entries) {
              if ((cDirs[pe.key] as String?) != 'input') {
                continue;
              }
              for (final b in pe.value as List) {
                if (b is! int) {
                  continue;
                }
                final drv = wireDriverCell[b];
                if (drv != null &&
                    comp.contains(drv) &&
                    !subComp.contains(drv)) {
                  subComp.add(drv);
                  bfsQueue.add(drv);
                }
              }
            }
          }

          if (subComp.length >= 2 && subComp.length < comp.length) {
            groupQueue.add(subComp);
          }
        }
        continue;
      }

      // Build the synthetic module's internal wire-ID space.
      final usedIds = <int>{};
      for (final cn in comp) {
        final cell = cells[cn];
        if (cell == null) {
          continue;
        }
        final conns = cell['connections'] as Map<String, dynamic>? ?? {};
        for (final bits in conns.values) {
          for (final b in bits as List) {
            if (b is int) {
              usedIds.add(b);
            }
          }
        }
      }

      var nextLocalId = 2;
      final idRemap = <int, int>{};
      for (final id in usedIds) {
        idRemap[id] = nextLocalId++;
      }

      List<Object> remapBits(List<Object> bits) =>
          bits.map((b) => b is int ? (idRemap[b] ?? b) : b).toList();

      // Build ports: one input port per input group, one output port per
      // output group.
      final childPorts = <String, Map<String, Object?>>{};
      final instanceConns = <String, List<Object>>{};
      final instancePortDirs = <String, String>{};

      for (final entry in inputGroups.entries) {
        final portName = 'in_${entry.key}';
        final parentBits = entry.value.cast<Object>();
        childPorts[portName] = {
          'direction': 'input',
          'bits': remapBits(parentBits),
        };
        instanceConns[portName] = parentBits;
        instancePortDirs[portName] = 'input';
      }

      for (final entry in outputGroups.entries) {
        final portName = 'out_${entry.key}';
        final parentBits = entry.value.cast<Object>();
        childPorts[portName] = {
          'direction': 'output',
          'bits': remapBits(parentBits),
        };
        instanceConns[portName] = parentBits;
        instancePortDirs[portName] = 'output';
      }

      // Re-map cells into the child's local ID space.
      final childCells = <String, Map<String, Object?>>{};
      for (final cn in comp) {
        final cell = Map<String, Object?>.from(cells[cn]!);
        final conns = Map<String, dynamic>.from(
            cell['connections']! as Map<String, dynamic>);
        for (final key in conns.keys.toList()) {
          conns[key] = remapBits((conns[key] as List).cast<Object>());
        }
        cell['connections'] = conns;
        childCells[cn] = cell;
      }

      // Build netnames for the child module.
      final childNetnames = <String, Object?>{};
      for (final pe in childPorts.entries) {
        childNetnames[pe.key] = {
          'bits': pe.value['bits'],
          'attributes': <String, Object?>{},
        };
      }

      final coveredIds = <int>{};
      for (final nn in childNetnames.values) {
        final bits = (nn! as Map<String, Object?>)['bits']! as List;
        for (final b in bits) {
          if (b is int) {
            coveredIds.add(b);
          }
        }
      }
      for (final cellEntry in childCells.entries) {
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
            childNetnames['${cellName}_$portName'] = {
              'bits': missingBits,
              'hide_name': 1,
              'attributes': <String, Object?>{},
            };
          }
        }
      }

      // Choose a name for the synthetic module type.
      final syntheticTypeName = 'struct_assign_${moduleName}_$groupIdx';
      final syntheticInstanceName = 'struct_assign_$groupIdx';
      groupIdx++;

      // Register the synthetic module definition.
      newModuleDefs[syntheticTypeName] = {
        'attributes': <String, Object?>{'src': 'generated'},
        'ports': childPorts,
        'cells': childCells,
        'netnames': childNetnames,
      };

      // Remove the grouped cells from the parent.
      claimedCells.addAll(comp);
      comp.forEach(cells.remove);

      // Add a hierarchical cell referencing the synthetic module.
      cells[syntheticInstanceName] = {
        'hide_name': 0,
        'type': syntheticTypeName,
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': instancePortDirs,
        'connections': instanceConns,
      };
    }
  }

  // Add all new synthetic module definitions.
  allModules.addAll(newModuleDefs);
}

/// Replace groups of `$slice` cells that share the same input bus and
/// whose outputs all feed into the same destination cell+port with a
/// single `$buf` cell.
///
/// This eliminates visual noise from struct-to-flat-bus decomposition
/// when the destination consumes the full struct value unchanged.
/// Both signal names (source struct and destination port) are preserved
/// as separate netnames connected through the buffer.
void applyStructBufferInsertion(
  Map<String, Map<String, Object?>> allModules,
) {
  for (final moduleName in allModules.keys.toList()) {
    final moduleDef = allModules[moduleName]!;
    final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
    if (cells == null || cells.isEmpty) {
      continue;
    }

    // Group $slice cells by their input bus (A bits).
    final slicesByInput = <String, List<String>>{};
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell['type'] != r'$slice') {
        continue;
      }
      final conns = cell['connections'] as Map<String, dynamic>?;
      if (conns == null) {
        continue;
      }
      final aBits = conns['A'] as List?;
      if (aBits == null) {
        continue;
      }
      final key = aBits.join(',');
      (slicesByInput[key] ??= []).add(entry.key);
    }

    var bufIdx = 0;
    for (final sliceGroup in slicesByInput.values) {
      if (sliceGroup.length < 2) {
        continue;
      }

      // Collect all Y output bit IDs from the group.
      final allYBitIds = <int>{};
      for (final sliceName in sliceGroup) {
        final cell = cells[sliceName]!;
        final conns = cell['connections']! as Map<String, dynamic>;
        for (final b in conns['Y']! as List) {
          if (b is int) {
            allYBitIds.add(b);
          }
        }
      }

      // Check: do all Y bits go to the same destination cell+port
      // (or a single module output port)?
      String? destId; // unique identifier for the destination
      var allSameDest = true;

      // Check cell port destinations.
      for (final otherEntry in cells.entries) {
        if (sliceGroup.contains(otherEntry.key)) {
          continue;
        }
        final otherConns =
            otherEntry.value['connections'] as Map<String, dynamic>? ?? {};
        for (final portEntry in otherConns.entries) {
          final bits = portEntry.value as List;
          if (bits.any((b) => b is int && allYBitIds.contains(b))) {
            final id = '${otherEntry.key}.${portEntry.key}';
            if (destId == null) {
              destId = id;
            } else if (destId != id) {
              allSameDest = false;
              break;
            }
          }
        }
        if (!allSameDest) {
          break;
        }
      }

      // Also check module output ports as potential destinations.
      final modPorts = moduleDef['ports'] as Map<String, Map<String, Object?>>?;
      if (allSameDest && modPorts != null) {
        for (final portEntry in modPorts.entries) {
          final port = portEntry.value;
          final dir = port['direction'] as String?;
          if (dir != 'output') {
            continue;
          }
          final bits = port['bits'] as List?;
          if (bits != null &&
              bits.any((b) => b is int && allYBitIds.contains(b))) {
            final id = '__port_${portEntry.key}';
            if (destId == null) {
              destId = id;
            } else if (destId != id) {
              allSameDest = false;
              break;
            }
          }
        }
      }

      if (!allSameDest || destId == null) {
        continue;
      }

      // Verify slices contiguously cover the full A bus.
      final firstSlice = cells[sliceGroup.first]!;
      final params0 = firstSlice['parameters'] as Map<String, Object?>?;
      final aWidth = params0?['A_WIDTH'] as int?;
      if (aWidth == null) {
        continue;
      }

      // Map offset → Y bits list, and validate.
      final coverageYBits = <int, List<Object>>{};
      var totalYBits = 0;
      var valid = true;
      for (final sliceName in sliceGroup) {
        final cell = cells[sliceName]!;
        final params = cell['parameters'] as Map<String, Object?>?;
        final offset = params?['OFFSET'] as int?;
        final yWidth = params?['Y_WIDTH'] as int?;
        if (offset == null || yWidth == null) {
          valid = false;
          break;
        }
        final conns = cell['connections']! as Map<String, dynamic>;
        final yBits = (conns['Y']! as List).cast<Object>();
        if (yBits.length != yWidth) {
          valid = false;
          break;
        }
        coverageYBits[offset] = yBits;
        totalYBits += yWidth;
      }
      if (!valid || totalYBits != aWidth) {
        continue;
      }

      // Verify contiguous coverage (no gaps or overlaps).
      final sortedOffsets = coverageYBits.keys.toList()..sort();
      var expectedOffset = 0;
      for (final off in sortedOffsets) {
        if (off != expectedOffset) {
          valid = false;
          break;
        }
        expectedOffset += coverageYBits[off]!.length;
      }
      if (!valid || expectedOffset != aWidth) {
        continue;
      }

      // Build the buffer cell.
      final firstConns = firstSlice['connections']! as Map<String, dynamic>;
      final aBus = (firstConns['A']! as List).cast<Object>();

      // Construct Y by concatenating slice outputs in offset order.
      final yBus = <Object>[];
      for (final off in sortedOffsets) {
        yBus.addAll(coverageYBits[off]!);
      }

      // Remove slice cells.
      sliceGroup.forEach(cells.remove);

      // Insert $buf cell.
      cells['struct_buf_$bufIdx'] = makeBufCell(aWidth, aBus, yBus);
      bufIdx++;
    }
  }
}

/// Replaces each `struct_assign_*` hierarchical instance in parent modules
/// with one `$buf` cell per output port and removes the synthetic module
/// definition.
///
/// For each output port the internal `$slice`/`$concat` routing is traced
/// back to the corresponding input-port bits so that each `$buf` connects
/// only the bits belonging to that specific net.  This keeps distinct
/// signal paths (e.g. `sum_0 → sumRpath` vs `sumP1 → sumPlusOneRpath`)
/// as separate cells so the schematic viewer can route them independently.
void collapseStructGroupModules(
  Map<String, Map<String, Object?>> allModules,
) {
  // Collect the names of all struct_assign module definitions to remove.
  final structAssignTypes = <String>{
    for (final name in allModules.keys)
      if (name.startsWith('struct_assign_')) name,
  };

  if (structAssignTypes.isEmpty) {
    return;
  }

  // Track which struct_assign types were fully collapsed (all instances
  // replaced).  Only those will have their definitions removed.
  final collapsedTypes = <String>{};
  final keptTypes = <String>{};

  // In each module, replace cells that instantiate a struct_assign type
  // with a $buf cell.
  for (final moduleDef in allModules.values) {
    final cells =
        moduleDef['cells'] as Map<String, Map<String, Object?>>? ?? {};

    final replacements = <String, Map<String, Object?>>{};
    final removals = <String>[];

    for (final entry in cells.entries) {
      final cellName = entry.key;
      final cell = entry.value;
      final type = cell['type'] as String?;
      if (type == null || !structAssignTypes.contains(type)) {
        continue;
      }

      final conns = cell['connections'] as Map<String, dynamic>? ?? {};

      // Look up the synthetic module definition so we can trace the
      // actual per-bit routing through its internal $slice/$concat cells.
      final synthDef = allModules[type];
      if (synthDef == null) {
        continue;
      }

      final synthPorts =
          synthDef['ports'] as Map<String, Map<String, Object?>>? ?? {};
      final synthCells =
          synthDef['cells'] as Map<String, Map<String, Object?>>? ?? {};

      // Map local (module-internal) input port bits → parent bit IDs,
      // and also record which input port name each local bit belongs to
      // plus its index within that port.
      final localToParent = <int, Object>{};
      final localBitToInputPort = <int, String>{};
      final localBitToIndex = <int, int>{};
      final inputPortWidths = <String, int>{};
      for (final pEntry in synthPorts.entries) {
        final dir = pEntry.value['direction'] as String?;
        if (dir != 'input' && dir != 'inout') {
          continue;
        }
        final localBits = (pEntry.value['bits'] as List?)?.cast<Object>() ?? [];
        final parentBits = (conns[pEntry.key] as List?)?.cast<Object>() ?? [];
        inputPortWidths[pEntry.key] = localBits.length;
        for (var i = 0; i < localBits.length && i < parentBits.length; i++) {
          if (localBits[i] is int) {
            localToParent[localBits[i] as int] = parentBits[i];
            localBitToInputPort[localBits[i] as int] = pEntry.key;
            localBitToIndex[localBits[i] as int] = i;
          }
        }
      }

      final inputPortBits = localToParent.keys.toSet();

      // Build a net-driver map inside the synthetic module by
      // processing its $slice, $concat, and $buf cells.
      final driver = <int, Object>{};

      for (final sc in synthCells.values) {
        final ct = sc['type'] as String?;
        final cc = sc['connections'] as Map<String, dynamic>? ?? {};
        final cp = sc['parameters'] as Map<String, Object?>? ?? {};

        if (ct == r'$slice') {
          final aBits = (cc['A'] as List?)?.cast<Object>() ?? [];
          final yBits = (cc['Y'] as List?)?.cast<Object>() ?? [];
          final offset = cp['OFFSET'] as int? ?? 0;
          final yWidth = yBits.length;
          final aWidth = aBits.length;
          final reversed = offset + yWidth > aWidth;
          for (var i = 0; i < yBits.length; i++) {
            if (yBits[i] is int) {
              final srcIdx = reversed ? (offset - i) : (offset + i);
              if (srcIdx >= 0 && srcIdx < aBits.length) {
                driver[yBits[i] as int] = aBits[srcIdx];
              }
            }
          }
        } else if (ct == r'$concat') {
          final yBits = (cc['Y'] as List?)?.cast<Object>() ?? [];

          // Gather input bits in LSB-first order.  Two formats:
          //   1. Standard 2-input: ports A (LSB) and B (MSB).
          //   2. Multi-input: range-named ports [lo:hi] with
          //      INx_WIDTH parameters — ordered by range start.
          final inputBits = <Object>[];
          if (cc.containsKey('A')) {
            inputBits
              ..addAll((cc['A'] as List?)?.cast<Object>() ?? <Object>[])
              ..addAll((cc['B'] as List?)?.cast<Object>() ?? <Object>[]);
          } else {
            // Multi-input concat: collect range-named ports ordered
            // by their starting bit position (LSB first).
            final rangePorts = <int, List<Object>>{};
            for (final portName in cc.keys) {
              if (portName == 'Y') {
                continue;
              }
              final m = rangePortRe.firstMatch(portName);
              if (m != null) {
                final hi = int.parse(m.group(1)!);
                final lo = m.group(2) != null ? int.parse(m.group(2)!) : hi;
                rangePorts[lo] = (cc[portName] as List?)?.cast<Object>() ?? [];
              }
            }
            final sortedKeys = rangePorts.keys.toList()..sort();
            for (final k in sortedKeys) {
              inputBits.addAll(rangePorts[k]!);
            }
          }

          for (var i = 0; i < yBits.length; i++) {
            if (yBits[i] is int && i < inputBits.length) {
              driver[yBits[i] as int] = inputBits[i];
            }
          }
        } else if (ct == r'$buf') {
          final aBits = (cc['A'] as List?)?.cast<Object>() ?? [];
          final yBits = (cc['Y'] as List?)?.cast<Object>() ?? [];
          for (var i = 0; i < yBits.length && i < aBits.length; i++) {
            if (yBits[i] is int) {
              driver[yBits[i] as int] = aBits[i];
            }
          }
        }
      }

      // Trace a local bit backwards through the driver map until we
      // reach an input port bit or a string constant.
      Object traceToSource(Object bit) {
        final visited = <int>{};
        var current = bit;
        while (current is int && !inputPortBits.contains(current)) {
          if (visited.contains(current)) {
            break;
          }
          visited.add(current);
          final next = driver[current];
          if (next == null) {
            break;
          }
          current = next;
        }
        return current;
      }

      // For each output port, trace its bits to their source and build
      // the appropriate cell type:
      //   $buf   – output has same width as its single source input port
      //   $slice – output is a contiguous sub-range of one input port
      //   $concat – output combines bits from multiple input ports
      final perPortCells = <String, Map<String, Object?>>{};
      var anyUnresolved = false;

      for (final pEntry in synthPorts.entries) {
        final dir = pEntry.value['direction'] as String?;
        if (dir != 'output') {
          continue;
        }
        final localBits = (pEntry.value['bits'] as List?)?.cast<Object>() ?? [];
        final parentBits = (conns[pEntry.key] as List?)?.cast<Object>() ?? [];

        final portOutputBits = <Object>[];
        final portInputBits = <Object>[];
        // Track per-bit source: local input-port bit ID (int) or null.
        final sourceBitIds = <int?>[];

        for (var i = 0; i < parentBits.length; i++) {
          portOutputBits.add(parentBits[i]);
          if (i < localBits.length) {
            final source = traceToSource(localBits[i]);
            if (source is int && localToParent.containsKey(source)) {
              portInputBits.add(localToParent[source]!);
              sourceBitIds.add(source);
            } else if (source is String) {
              portInputBits.add(source);
              sourceBitIds.add(null);
            } else {
              portInputBits.add('x');
              sourceBitIds.add(null);
            }
          } else {
            portInputBits.add('x');
            sourceBitIds.add(null);
          }
        }

        if (portInputBits.contains('x')) {
          anyUnresolved = true;
          break;
        }

        if (portOutputBits.isEmpty) {
          continue;
        }

        // Determine which input port(s) source this output port.
        final sourcePortNames = <String>{};
        for (final sid in sourceBitIds) {
          if (sid != null && localBitToInputPort.containsKey(sid)) {
            sourcePortNames.add(localBitToInputPort[sid]!);
          }
        }

        final cellKey = '${cellName}_${pEntry.key}';

        if (sourcePortNames.length == 1) {
          final srcPort = sourcePortNames.first;
          final srcWidth = inputPortWidths[srcPort] ?? 0;
          if (portOutputBits.length == srcWidth) {
            // Same width → $buf
            perPortCells['${cellKey}_buf'] = makeBufCell(
                portOutputBits.length, portInputBits, portOutputBits);
          } else {
            // Subset of one input port → $slice.  Determine the offset
            // from the first traced bit's index within its input port.
            final firstIdx = sourceBitIds.first;
            final offset =
                firstIdx != null ? (localBitToIndex[firstIdx] ?? 0) : 0;
            perPortCells['${cellKey}_slice'] = makeSliceCell(
                offset,
                srcWidth,
                portOutputBits.length,
                (conns[srcPort] as List?)?.cast<Object>() ?? [],
                portOutputBits);
          }
        } else {
          // Multiple source ports – should be rare after the grouping
          // guard excludes multi-source concats.  Fall back to $buf.
          perPortCells['${cellKey}_buf'] =
              makeBufCell(portOutputBits.length, portInputBits, portOutputBits);
        }
      }

      if (perPortCells.isEmpty) {
        continue;
      }

      // Only collapse pure passthroughs: every output bit must trace
      // back to an input-port bit or a string constant.  If any bit
      // fell through as 'x' the module is doing real computation
      // (e.g. addition, muxing) and should be kept as a hierarchy.
      if (anyUnresolved) {
        keptTypes.add(type);
        continue;
      }

      collapsedTypes.add(type);
      removals.add(cellName);
      replacements.addAll(perPortCells);
    }

    removals.forEach(cells.remove);
    cells.addAll(replacements);
  }

  // Remove only the synthetic module definitions whose instances were all
  // successfully collapsed.  Types that had at least one non-passthrough
  // instance must keep their definition so the hierarchy is preserved.
  collapsedTypes.difference(keptTypes).forEach(allModules.remove);
}

/// Replace standalone `$concat` cells whose input bits all originate
/// from a single module input (or inout) port and cover its full width
/// with a simple `$buf` cell.
///
/// This eliminates the visual noise of struct-to-bitvector reassembly
/// when an input [LogicStructure] port is decomposed into fields and
/// immediately re-packed via a [Swizzle].
void applyConcatToBufferReplacement(
  Map<String, Map<String, Object?>> allModules,
) {
  for (final moduleDef in allModules.values) {
    final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
    if (cells == null || cells.isEmpty) {
      continue;
    }

    final modPorts = moduleDef['ports'] as Map<String, Map<String, Object?>>?;
    if (modPorts == null) {
      continue;
    }

    // Build bit → port-name map for input / inout ports.
    final bitToPort = <int, String>{};
    for (final portEntry in modPorts.entries) {
      final dir = portEntry.value['direction'] as String?;
      if (dir != 'input' && dir != 'inout') {
        continue;
      }
      final bits = portEntry.value['bits'] as List? ?? [];
      for (final b in bits) {
        if (b is int) {
          bitToPort[b] = portEntry.key;
        }
      }
    }

    final removals = <String>[];
    final additions = <String, Map<String, Object?>>{};
    var bufIdx = 0;

    // Avoid name collisions with existing concat_buf_* cells.
    for (final name in cells.keys) {
      if (name.startsWith('concat_buf_')) {
        final idx = int.tryParse(name.substring('concat_buf_'.length));
        if (idx != null && idx >= bufIdx) {
          bufIdx = idx + 1;
        }
      }
    }

    for (final entry in cells.entries) {
      final cell = entry.value;
      if ((cell['type'] as String?) != r'$concat') {
        continue;
      }

      final conns = cell['connections'] as Map<String, dynamic>? ?? {};
      final pdirs = cell['port_directions'] as Map<String, dynamic>? ?? {};

      // Collect input ranges and the Y output.
      // Port names follow the pattern "[upper:lower]" or "[bit]".
      final rangedInputs = <int, List<Object>>{}; // lower → bits
      List<Object>? yBits;

      for (final pe in conns.entries) {
        final dir = pdirs[pe.key] as String? ?? '';
        final bits = (pe.value as List).cast<Object>();
        if (dir == 'output' && pe.key == 'Y') {
          yBits = bits;
          continue;
        }
        if (dir != 'input') {
          continue;
        }
        // Parse "[upper:lower]" or "[bit]".
        final match = rangePortRe.firstMatch(pe.key);
        if (match == null) {
          // Also accept the 2-input A/B form.
          if (pe.key == 'A') {
            rangedInputs[0] = bits;
          } else if (pe.key == 'B') {
            // Determine A width to set the offset.
            final aBits = conns['A'] as List?;
            if (aBits != null) {
              rangedInputs[aBits.length] = bits;
            }
          }
          continue;
        }
        final upper = int.parse(match.group(1)!);
        final lower =
            match.group(2) != null ? int.parse(match.group(2)!) : upper;
        rangedInputs[lower] = bits;
      }

      if (yBits == null || rangedInputs.isEmpty) {
        continue;
      }

      // Assemble input bits in LSB-to-MSB order.
      final sortedLowers = rangedInputs.keys.toList()..sort();
      final allInputBits = <Object>[];
      for (final lower in sortedLowers) {
        allInputBits.addAll(rangedInputs[lower]!);
      }

      // Check that every input bit belongs to the same module port.
      String? sourcePort;
      var allFromSamePort = true;
      for (final b in allInputBits) {
        if (b is! int) {
          allFromSamePort = false;
          break;
        }
        final port = bitToPort[b];
        if (port == null) {
          allFromSamePort = false;
          break;
        }
        sourcePort ??= port;
        if (port != sourcePort) {
          allFromSamePort = false;
          break;
        }
      }

      if (!allFromSamePort || sourcePort == null) {
        continue;
      }

      // Verify full-width coverage of the source port.
      final portBits = modPorts[sourcePort]!['bits']! as List;
      if (allInputBits.length != portBits.length) {
        continue;
      }

      // Replace $concat with $buf.
      removals.add(entry.key);
      additions['concat_buf_$bufIdx'] =
          makeBufCell(allInputBits.length, allInputBits, yBits);
      bufIdx++;
    }

    removals.forEach(cells.remove);
    cells.addAll(additions);
  }
}
