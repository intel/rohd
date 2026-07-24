// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_passes.dart
// Post-processing optimization passes for netlist synthesis.
//
// 2025 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_synthesis_result.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_utils.dart';

/// Post-processing optimization passes for netlist synthesis.
///
/// All methods are static — no instances are created.
@internal
class NetlistPasses {
  /// Prevents construction of this static utility class.
  NetlistPasses._();

  /// Collects a combined modules map from [SynthesisResult]s suitable for
  /// JSON emission.
  static Map<String, Map<String, Object?>> collectModuleEntries(
    Iterable<SynthesisResult> results, {
    Module? topModule,
    bool includeCellConnections = true,
  }) {
    final allModules = <String, Map<String, Object?>>{};
    for (final result in results) {
      if (result is NetlistSynthesisResult) {
        final typeName = result.instanceTypeName;
        final attrs = _copyObjectMap(result.attributes);
        if (topModule != null && result.module == topModule) {
          attrs['top'] = 1;
        }
        allModules[typeName] = {
          'attributes': attrs,
          'ports': _copyNestedMaps(result.ports),
          'cells': _copyCells(
            result.cells,
            includeConnections: includeCellConnections,
          ),
          'netnames': _copyObjectMap(result.netnames),
        };
      }
    }
    return allModules;
  }

  /// Deep-copies cell maps, optionally omitting connection payloads.
  static Map<String, Map<String, Object?>> _copyCells(
    Map<String, Map<String, Object?>> source, {
    required bool includeConnections,
  }) =>
      {
        for (final entry in source.entries)
          entry.key: _copyObjectMap(
            includeConnections
                ? entry.value
                : (Map<String, Object?>.of(entry.value)..remove('connections')),
          ),
      };

  /// Deep-copies a map whose values are JSON-like object maps.
  static Map<String, Map<String, Object?>> _copyNestedMaps(
    Map<String, Map<String, Object?>> source,
  ) =>
      {
        for (final entry in source.entries)
          entry.key: _copyObjectMap(entry.value),
      };

  /// Deep-copies a JSON-like object map.
  static Map<String, Object?> _copyObjectMap(Map<String, Object?> source) => {
        for (final entry in source.entries)
          entry.key: _copyJsonValue(entry.value),
      };

  /// Deep-copies a JSON-like value while preserving scalar objects.
  static Object? _copyJsonValue(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key as String: _copyJsonValue(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final element in value) _copyJsonValue(element)];
    }
    return value;
  }

  // ════════════════════════════════════════════════════════════════════
  //  Unified transparent-cell clustering
  // ════════════════════════════════════════════════════════════════════

  /// Transparent cell types that only reshuffle / rename bits.
  static const _transparentTypes = {
    r'$buf',
    r'$slice',
    r'$concat',
    r'$struct_unpack',
    r'$struct_pack',
  };

  /// Unified transparent-cell clustering pass.
  ///
  /// **Phase 1 — Cluster identification:**
  /// Builds an undirected graph over transparent cells (two cells are
  /// neighbours when one's output wire feeds the other's input) and
  /// finds connected components via BFS.
  ///
  /// **Phase 2 — Cluster collapse:**
  /// For every multi-cell component, traces each externally-consumed
  /// output bit backward through the component's bit-level mapping
  /// until reaching an external source bit, then replaces the entire
  /// component with a single `$buf` wired from traced sources to
  /// destinations.
  static void applyTransparentClustering(
    Map<String, Map<String, Object?>> allModules,
  ) {
    for (final moduleDef in allModules.values) {
      final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
      if (cells == null || cells.isEmpty) {
        continue;
      }

      final ports = moduleDef['ports'] as Map<String, dynamic>? ?? {};

      // ── Gather transparent cells ──

      final tCells = <String>{
        for (final e in cells.entries)
          if (_transparentTypes.contains(e.value['type'] as String?)) e.key,
      };
      if (tCells.isEmpty) {
        continue;
      }

      // ── Wire maps ──

      final wireConsumers = <int, Set<String>>{};

      for (final e in cells.entries) {
        final dirs = e.value['port_directions'] as Map<String, dynamic>? ?? {};
        final conns = e.value['connections'] as Map<String, dynamic>? ?? {};
        for (final pe in conns.entries) {
          if ((dirs[pe.key] as String?) == 'output') {
            continue;
          }
          for (final b in pe.value as List) {
            if (b is int) {
              (wireConsumers[b] ??= {}).add(e.key);
            }
          }
        }
      }

      // Bits consumed by module output / inout ports.
      final portOutBits = <int>{};
      for (final pv in ports.values) {
        final pm = pv as Map<String, dynamic>;
        final dir = pm['direction'] as String?;
        if (dir == 'output' || dir == 'inout') {
          for (final b in pm['bits'] as List) {
            if (b is int) {
              portOutBits.add(b);
            }
          }
        }
      }

      // ── Phase 1: connected components ──

      final adj = <String, Set<String>>{for (final tc in tCells) tc: {}};

      for (final tc in tCells) {
        final dirs =
            cells[tc]!['port_directions'] as Map<String, dynamic>? ?? {};
        final conns = cells[tc]!['connections'] as Map<String, dynamic>? ?? {};
        for (final pe in conns.entries) {
          if ((dirs[pe.key] as String?) != 'output') {
            continue;
          }
          for (final b in pe.value as List) {
            if (b is! int) {
              continue;
            }
            for (final c in wireConsumers[b] ?? const <String>{}) {
              if (c != tc && tCells.contains(c)) {
                adj[tc]!.add(c);
                adj[c]!.add(tc);
              }
            }
          }
        }
      }

      final visited = <String>{};
      final components = <Set<String>>[];

      for (final tc in tCells) {
        if (!visited.add(tc)) {
          continue;
        }
        final comp = <String>{tc};
        final stack = [tc];
        while (stack.isNotEmpty) {
          final cur = stack.removeLast();
          for (final nb in adj[cur]!) {
            if (visited.add(nb)) {
              comp.add(nb);
              stack.add(nb);
            }
          }
        }
        if (comp.length >= 2) {
          components.add(comp);
        }
      }

      if (components.isEmpty) {
        continue;
      }

      // ── Phase 2: trace & replace ──

      final cellsToRemove = <String>{};
      final cellsToAdd = <String, Map<String, Object?>>{};

      for (final comp in components) {
        if (comp.any(
          (cn) => const {
            r'$concat',
            r'$struct_pack',
            r'$struct_unpack',
          }.contains(cells[cn]!['type']),
        )) {
          continue;
        }

        // Build output-bit → input-bit map for the whole cluster.
        final bitMap = <int, Object>{};
        for (final cn in comp) {
          _mapCellBits(cells[cn]!, bitMap);
        }

        // External output bits: produced by the cluster but consumed
        // by something outside it (another cell or module output port).
        final extOut = <int>[];
        for (final cn in comp) {
          final dirs =
              cells[cn]!['port_directions'] as Map<String, dynamic>? ?? {};
          final conns =
              cells[cn]!['connections'] as Map<String, dynamic>? ?? {};
          for (final pe in conns.entries) {
            if ((dirs[pe.key] as String?) != 'output') {
              continue;
            }
            for (final b in pe.value as List) {
              if (b is! int) {
                continue;
              }
              if (portOutBits.contains(b) ||
                  (wireConsumers[b]?.any((c) => !comp.contains(c)) ?? false)) {
                extOut.add(b);
              }
            }
          }
        }

        if (extOut.isEmpty) {
          // Fully dead cluster — remove.
          cellsToRemove.addAll(comp);
          continue;
        }

        // Trace each external output back through the cluster to an
        // external source bit.
        final aList = <Object>[];
        final yList = <Object>[];
        var ok = true;

        for (final ob in extOut) {
          Object cur = ob;
          final seen = <int>{};
          while (cur is int && bitMap.containsKey(cur)) {
            if (!seen.add(cur)) {
              ok = false;
              break;
            }
            cur = bitMap[cur]!;
          }
          if (!ok) {
            break;
          }
          aList.add(cur);
          yList.add(ob);
        }

        if (!ok) {
          continue;
        }

        cellsToAdd['cluster_buf_${comp.first}'] = NetlistUtils.makeBufCell(
          aList.length,
          aList,
          yList,
        );
        cellsToRemove.addAll(comp);
      }

      cellsToRemove.forEach(cells.remove);
      cells.addAll(cellsToAdd);
    }
  }

  /// Removes transparent helper cells whose outputs are not consumed by any
  /// other cell or module output.
  static void removeUnconsumedTransparentCells(
    Map<String, Map<String, Object?>> allModules,
  ) {
    for (final moduleDef in allModules.values) {
      final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
      if (cells == null || cells.isEmpty) {
        continue;
      }

      final ports = moduleDef['ports'] as Map<String, dynamic>? ?? {};
      var changed = true;
      while (changed) {
        changed = false;
        final consumedBits = <int>{};

        for (final cell in cells.values) {
          final dirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
          final conns = cell['connections'] as Map<String, dynamic>? ?? {};
          for (final entry in conns.entries) {
            final direction = dirs[entry.key] as String?;
            if (direction != 'input' && direction != 'inout') {
              continue;
            }
            consumedBits.addAll((entry.value as List).whereType<int>());
          }
        }
        for (final port in ports.values) {
          final portMap = port as Map<String, dynamic>;
          final direction = portMap['direction'] as String?;
          if (direction != 'output' && direction != 'inout') {
            continue;
          }
          consumedBits.addAll((portMap['bits'] as List).whereType<int>());
        }

        cells.removeWhere((_, cell) {
          if (!_transparentTypes.contains(cell['type'] as String?)) {
            return false;
          }
          final dirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
          final conns = cell['connections'] as Map<String, dynamic>? ?? {};
          final outputBits = <int>{};
          for (final entry in conns.entries) {
            final direction = dirs[entry.key] as String?;
            if (direction != 'output' && direction != 'inout') {
              continue;
            }
            outputBits.addAll((entry.value as List).whereType<int>());
          }
          final remove =
              outputBits.isNotEmpty && !outputBits.any(consumedBits.contains);
          changed = changed || remove;
          return remove;
        });
      }
    }
  }

  /// Removes `$concat` cells that only rename an already-named bit vector.
  ///
  /// Explicit array concat cells are useful when they show a real regrouping,
  /// but a concat whose flattened inputs exactly match an existing netname is
  /// just an alias. Redirect its consumers to the named source bits and remove
  /// the cell.
  static void removeTrivialConcatAliases(
    Map<String, Map<String, Object?>> allModules,
  ) {
    for (final moduleDef in allModules.values) {
      final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
      final netnames = moduleDef['netnames'] as Map<String, Object?>?;
      if (cells == null || cells.isEmpty || netnames == null) {
        continue;
      }

      final namedBitVectors = [
        for (final rawNetname in netnames.values)
          if (rawNetname is Map && rawNetname['bits'] is List)
            (rawNetname['bits'] as List).cast<Object>(),
      ];
      if (namedBitVectors.isEmpty) {
        continue;
      }

      var changed = true;
      while (changed) {
        changed = false;
        final replacementByOutputBit = <int, Object>{};
        final cellsToRemove = <String>{};

        for (final entry in cells.entries) {
          final cell = entry.value;
          if (cell['type'] != r'$concat' ||
              entry.key.startsWith('array_concat_output_')) {
            continue;
          }

          final dirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
          final conns = cell['connections'] as Map<String, dynamic>? ?? {};
          final outputBits = <Object>[];
          final inputBits = <Object>[];

          for (final portEntry in conns.entries) {
            final bits = (portEntry.value as List).cast<Object>();
            if ((dirs[portEntry.key] as String?) == 'output') {
              outputBits.addAll(bits);
            } else {
              inputBits.addAll(bits);
            }
          }

          if (outputBits.length != inputBits.length ||
              !_matchesNamedVector(inputBits, namedBitVectors)) {
            continue;
          }

          for (var index = 0; index < outputBits.length; index++) {
            final outputBit = outputBits[index];
            if (outputBit is int) {
              replacementByOutputBit[outputBit] = inputBits[index];
            }
          }
          cellsToRemove.add(entry.key);
        }

        if (replacementByOutputBit.isEmpty) {
          continue;
        }

        void rewriteBits(List<Object> bits) {
          for (var index = 0; index < bits.length; index++) {
            final bit = bits[index];
            if (bit is int && replacementByOutputBit.containsKey(bit)) {
              bits[index] = replacementByOutputBit[bit]!;
            }
          }
        }

        final ports = moduleDef['ports'] as Map<String, dynamic>? ?? {};
        for (final rawPort in ports.values) {
          final port = rawPort as Map<String, dynamic>;
          rewriteBits((port['bits'] as List).cast<Object>());
        }

        for (final entry in cells.entries) {
          if (cellsToRemove.contains(entry.key)) {
            continue;
          }
          final cell = entry.value;
          final conns = cell['connections'] as Map<String, dynamic>? ?? {};
          for (final rawBits in conns.values) {
            rewriteBits((rawBits as List).cast<Object>());
          }
        }

        for (final rawNetname in netnames.values) {
          if (rawNetname is Map && rawNetname['bits'] is List) {
            rewriteBits((rawNetname['bits'] as List).cast<Object>());
          }
        }

        cellsToRemove.forEach(cells.remove);
        changed = true;
      }
    }
  }

  /// Replaces a `$concat` of adjacent `$slice` outputs from the same source
  /// with one wider `$slice`.
  static void collapseConcatOfAdjacentSlices(
    Map<String, Map<String, Object?>> allModules,
  ) {
    for (final moduleDef in allModules.values) {
      final cells = moduleDef['cells'] as Map<String, Map<String, Object?>>?;
      if (cells == null || cells.isEmpty) {
        continue;
      }

      final ports = moduleDef['ports'] as Map<String, dynamic>? ?? {};
      final cellsToRemove = <String>{};

      for (final concatEntry in cells.entries.toList()) {
        final concat = concatEntry.value;
        if (concat['type'] != r'$concat' ||
            concatEntry.key.startsWith('array_concat_output_')) {
          continue;
        }

        final concatDirs =
            concat['port_directions'] as Map<String, dynamic>? ?? {};
        final concatConns =
            concat['connections'] as Map<String, dynamic>? ?? {};
        final inputSliceRefs = <({String name, Map<String, Object?> cell})>[];
        final outputBits = <Object>[];
        var valid = true;

        for (final portEntry in concatConns.entries) {
          if ((concatDirs[portEntry.key] as String?) == 'output') {
            outputBits.addAll((portEntry.value as List).cast<Object>());
            continue;
          }

          final inputBits = (portEntry.value as List).cast<Object>();
          final sliceEntry = _findSliceDrivingBits(cells, inputBits);
          if (sliceEntry == null) {
            valid = false;
            break;
          }
          inputSliceRefs.add((name: sliceEntry.key, cell: sliceEntry.value));
        }

        if (!valid || inputSliceRefs.isEmpty || outputBits.isEmpty) {
          continue;
        }

        final firstSlice = inputSliceRefs.first.cell;
        final firstParams =
            firstSlice['parameters'] as Map<String, dynamic>? ?? {};
        final firstConnections =
            firstSlice['connections'] as Map<String, dynamic>?;
        final sourceRawBits = firstConnections?['A'] as List?;
        if (sourceRawBits == null) {
          continue;
        }
        final sourceBits = sourceRawBits.cast<Object>();
        final startOffset = firstParams['OFFSET'] as int?;
        final sourceWidth = firstParams['A_WIDTH'] as int?;
        if (startOffset == null || sourceWidth == null) {
          continue;
        }

        var expectedOffset = startOffset;
        var combinedWidth = 0;
        for (final sliceRef in inputSliceRefs) {
          final slice = sliceRef.cell;
          final params = slice['parameters'] as Map<String, dynamic>? ?? {};
          final conns = slice['connections'] as Map<String, dynamic>? ?? {};
          final sliceSourceBits = (conns['A'] as List).cast<Object>();
          final offset = params['OFFSET'] as int?;
          final width = params['Y_WIDTH'] as int?;

          if (offset != expectedOffset ||
              width == null ||
              params['A_WIDTH'] != sourceWidth ||
              !_sameBits(sliceSourceBits, sourceBits)) {
            valid = false;
            break;
          }

          expectedOffset += width;
          combinedWidth += width;
        }

        if (!valid || combinedWidth != outputBits.length) {
          continue;
        }

        cells[concatEntry.key] = {
          'hide_name': concat['hide_name'] ?? 0,
          'type': r'$slice',
          'parameters': <String, Object?>{
            'OFFSET': startOffset,
            'A_WIDTH': sourceWidth,
            'Y_WIDTH': combinedWidth,
          },
          'attributes': concat['attributes'] ?? <String, Object?>{},
          'port_directions': <String, String>{'A': 'input', 'Y': 'output'},
          'connections': <String, List<Object>>{
            'A': sourceBits,
            'Y': outputBits,
          },
        };

        for (final sliceRef in inputSliceRefs) {
          if (!_sliceOutputConsumedOutside(
            sliceRef.name,
            sliceRef.cell,
            cells,
            ports,
          )) {
            cellsToRemove.add(sliceRef.name);
          }
        }
      }

      cellsToRemove.forEach(cells.remove);
    }
  }

  /// Finds a slice cell whose output bits exactly match [bits].
  static MapEntry<String, Map<String, Object?>>? _findSliceDrivingBits(
    Map<String, Map<String, Object?>> cells,
    List<Object> bits,
  ) {
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell['type'] != r'$slice') {
        continue;
      }
      final conns = cell['connections'] as Map<String, dynamic>? ?? {};
      final yBits = (conns['Y'] as List?)?.cast<Object>();
      if (yBits != null && _sameBits(yBits, bits)) {
        return entry;
      }
    }
    return null;
  }

  /// Checks whether a slice output is still consumed outside that slice cell.
  static bool _sliceOutputConsumedOutside(
    String sliceName,
    Map<String, Object?> slice,
    Map<String, Map<String, Object?>> cells,
    Map<String, dynamic> ports,
  ) {
    final sliceConns = slice['connections'] as Map<String, dynamic>? ?? {};
    final outputBits =
        ((sliceConns['Y'] as List?) ?? const []).whereType<int>();
    final outputBitSet = outputBits.toSet();
    if (outputBitSet.isEmpty) {
      return false;
    }

    for (final rawPort in ports.values) {
      final port = rawPort as Map<String, dynamic>;
      final direction = port['direction'] as String?;
      if (direction != 'output' && direction != 'inout') {
        continue;
      }
      final bits = (port['bits'] as List).whereType<int>();
      if (bits.any(outputBitSet.contains)) {
        return true;
      }
    }

    for (final entry in cells.entries) {
      if (entry.key == sliceName) {
        continue;
      }
      final cell = entry.value;
      final dirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
      final conns = cell['connections'] as Map<String, dynamic>? ?? {};
      for (final portEntry in conns.entries) {
        final direction = dirs[portEntry.key] as String?;
        if (direction != 'input' && direction != 'inout') {
          continue;
        }
        final bits = (portEntry.value as List).whereType<int>();
        if (bits.any(outputBitSet.contains)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks whether [bits] exactly matches any known named bit vector.
  static bool _matchesNamedVector(
    List<Object> bits,
    List<List<Object>> namedBitVectors,
  ) =>
      namedBitVectors.any(
        (namedBits) =>
            namedBits.length == bits.length &&
            namedBits.indexed.every((entry) => entry.$2 == bits[entry.$1]),
      );

  /// Checks whether two bit vectors have identical contents and order.
  static bool _sameBits(List<Object> left, List<Object> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);

  /// Populates [bitMap] with output-wire-bit → input-wire-bit entries
  /// for a single transparent cell.
  static void _mapCellBits(Map<String, Object?> cell, Map<int, Object> bitMap) {
    final type = cell['type']! as String;
    final dirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
    final conns = cell['connections'] as Map<String, dynamic>? ?? {};
    final params = cell['parameters'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case r'$buf':
        _mapPairwise(conns['A'] as List, conns['Y'] as List, bitMap);

      case r'$slice':
        final a = conns['A'] as List;
        final y = conns['Y'] as List;
        final off = params['OFFSET'] as int? ?? 0;
        for (var i = 0; i < y.length; i++) {
          if (y[i] is int && (off + i) < a.length) {
            bitMap[y[i] as int] = a[off + i] as Object;
          }
        }

      case r'$concat':
        final y = conns['Y'] as List;
        // Input ports are in connection-map order; their bits
        // concatenate to form Y (first port at LSB).
        final inBits = <Object>[
          for (final pe in conns.entries)
            if ((dirs[pe.key] as String?) != 'output')
              ...(pe.value as List).cast<Object>(),
        ];
        _mapPairwise(inBits, y, bitMap);

      case r'$struct_unpack':
        final a = conns['A'] as List;
        final fc = params['FIELD_COUNT'] as int? ?? 0;
        for (var f = 0; f < fc; f++) {
          final fn = params['FIELD_${f}_NAME'] as String?;
          final fo = params['FIELD_${f}_OFFSET'] as int? ?? 0;
          if (fn == null) {
            continue;
          }
          final fb = conns[fn] as List?;
          if (fb == null) {
            continue;
          }
          for (var i = 0; i < fb.length; i++) {
            if (fb[i] is int && (fo + i) < a.length) {
              bitMap[fb[i] as int] = a[fo + i] as Object;
            }
          }
        }

      case r'$struct_pack':
        final y = conns['Y'] as List;
        final fc = params['FIELD_COUNT'] as int? ?? 0;
        final src = List<Object?>.filled(y.length, null);
        for (var f = 0; f < fc; f++) {
          final fn = params['FIELD_${f}_NAME'] as String?;
          final fo = params['FIELD_${f}_OFFSET'] as int? ?? 0;
          if (fn == null) {
            continue;
          }
          final fb = conns[fn] as List?;
          if (fb == null) {
            continue;
          }
          for (var i = 0; i < fb.length; i++) {
            if ((fo + i) < src.length) {
              src[fo + i] = fb[i];
            }
          }
        }
        for (var i = 0; i < y.length; i++) {
          if (y[i] is int && src[i] != null) {
            bitMap[y[i] as int] = src[i]!;
          }
        }
    }
  }

  /// Maps `Y[i]` → `A[i]` for identity-shaped cells.
  static void _mapPairwise(
    List<dynamic> a,
    List<dynamic> y,
    Map<int, Object> bitMap,
  ) {
    for (var i = 0; i < y.length && i < a.length; i++) {
      if (y[i] is int) {
        bitMap[y[i] as int] = a[i] as Object;
      }
    }
  }
}
