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

/// Post-processing optimization passes for netlist synthesis.
///
/// All methods are static — no instances are created.
class NetlistPasses {
  NetlistPasses._();

  /// Collects a combined modules map from [SynthesisResult]s suitable for
  /// JSON emission.
  static Map<String, Map<String, Object?>> collectModuleEntries(
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
