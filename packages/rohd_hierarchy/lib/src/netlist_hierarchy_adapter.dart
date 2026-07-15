// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_hierarchy_adapter.dart
// Hierarchy adapter for netlist JSON format (derived from Yosys JSON)
// using rohd_hierarchy.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd_hierarchy/src/base_hierarchy_adapter.dart';
import 'package:rohd_hierarchy/src/hierarchy_models.dart';

/// Adapter that exposes a netlist as a source-agnostic hierarchy.
///
/// Extends [BaseHierarchyAdapter] from rohd_hierarchy package, using the shared
/// implementation for search, autocomplete, and lookup methods.
/// Only the netlist format-specific
/// JSON parsing logic is implemented here.
///
/// Features:
/// - Parses ports, netnames, and cells from netlist JSON
/// - Filters auto-generated netnames (`hide_name`, `$`-prefixed, port dupes)
/// - Extracts `port_directions` on primitive cells for signal visibility
/// - Supports optional root-name override for VCD name alignment
class NetlistHierarchyAdapter extends BaseHierarchyAdapter {
  NetlistHierarchyAdapter._();

  /// Convenience factory to parse a netlist JSON string directly.
  ///
  /// [rootNameOverride] replaces the top-module name derived from the JSON.
  /// Use this when VCD scopes use instance names that differ from the
  /// definition names in the netlist output (often capitalized).
  factory NetlistHierarchyAdapter.fromJson(
    String netlistJson, {
    String? rootNameOverride,
  }) {
    final obj = jsonDecode(netlistJson);
    if (obj is! Map<String, dynamic>) {
      throw const FormatException('Invalid netlist JSON root');
    }
    return NetlistHierarchyAdapter.fromMap(
      obj,
      rootNameOverride: rootNameOverride,
    );
  }

  /// Factory to parse a pre-decoded netlist JSON map.
  ///
  /// [netlistJson] must contain a top-level `modules` key.
  /// [rootNameOverride] optionally replaces the detected top-module name.
  factory NetlistHierarchyAdapter.fromMap(
    Map<String, dynamic> netlistJson, {
    String? rootNameOverride,
  }) {
    final adapter = NetlistHierarchyAdapter._()
      .._buildFromNetlist(netlistJson, rootNameOverride: rootNameOverride);
    return adapter;
  }

  void _buildFromNetlist(
    Map<String, dynamic> netlistJson, {
    String? rootNameOverride,
  }) {
    final modules = netlistJson['modules'] as Map<String, dynamic>?;
    if (modules == null || modules.isEmpty) {
      throw const FormatException('Netlist JSON contained no modules');
    }

    // Find top module or default to first
    final topName = modules.entries
            .where(
              (e) =>
                  ((e.value as Map<String, dynamic>)['attributes']
                      as Map<String, dynamic>?)?['top'] ==
                  1,
            )
            .map((e) => e.key)
            .firstOrNull ??
        modules.keys.first;

    final resolvedRootName = rootNameOverride ?? topName;

    final rootNode = _parseModule(
      name: resolvedRootName,
      definition: topName,
      moduleData: modules[topName] as Map<String, dynamic>,
      allModules: modules,
    );
    root = rootNode;
    rootNode.buildAddresses();
  }

  /// Parse a module definition and return the created
  /// [HierarchyOccurrence].
  HierarchyOccurrence _parseModule({
    required String name,
    required String definition,
    required Map<String, dynamic> moduleData,
    required Map<String, dynamic> allModules,
  }) {
    // Ports (signals with direction)
    final portsData = moduleData['ports'] as Map<String, dynamic>?;
    final signalsList = <SignalOccurrence>[
      if (portsData != null)
        ...portsData.entries.indexed.map((entry) {
          final (idx, kv) = entry;
          final p = kv.value as Map<String, dynamic>;
          final dir = p['direction']?.toString() ?? 'inout';
          final bits = (p['bits'] as List?)?.length ?? 0;
          final logicType = p['logic_type'] as Map<String, dynamic>?;
          return SignalOccurrence(
            name: kv.key,
            direction: dir,
            width: bits > 0 ? bits : 1,
            portIndex: idx,
            logicType: logicType,
          );
        }),
    ];

    // Netnames (internal signals without direction).
    // Netlist `netnames` contains ALL named signals including port-connected
    // ones.  We skip names already covered by `ports` above, as well as
    // auto-generated names (hide_name=1 or $-prefixed).
    final netsData = moduleData['netnames'] as Map<String, dynamic>?;
    if (netsData != null) {
      final portNames = portsData?.keys.toSet() ?? <String>{};
      signalsList.addAll(
        netsData.entries
            .where(
          (entry) =>
              !portNames.contains(entry.key) &&
              !entry.key.startsWith(r'$') &&
              () {
                final h = (entry.value as Map<String, dynamic>)['hide_name'];
                return h != 1 && h != '1';
              }(),
        )
            .map((entry) {
          final netData = entry.value as Map<String, dynamic>;
          final bits = (netData['bits'] as List?)?.length ?? 0;
          final attrs = netData['attributes'] as Map<String, dynamic>?;
          final isComputed =
              attrs?['computed'] == 1 || attrs?['computed'] == true;
          final logicType = netData['logic_type'] as Map<String, dynamic>?;
          return SignalOccurrence(
            name: entry.key,
            width: bits > 0 ? bits : 1,
            isComputed: isComputed,
            logicType: logicType,
          );
        }),
      );
    }

    // Cells -> submodules or instances
    final childNodes = <HierarchyOccurrence>[];
    final cells = moduleData['cells'] as Map<String, dynamic>?;
    if (cells != null) {
      for (final entry in cells.entries) {
        final cellName = entry.key;
        final cellData = entry.value as Map<String, dynamic>;
        final cellType = cellData['type']?.toString() ?? '';

        if (allModules.containsKey(cellType) &&
            !HierarchyOccurrence.isPrimitiveType(cellType)) {
          final childNode = _parseModule(
            name: cellName,
            definition: cellType,
            moduleData: allModules[cellType] as Map<String, dynamic>,
            allModules: allModules,
          );
          childNodes.add(childNode);
        } else {
          // Primitive cell — create leaf occurrence.
          // Extract port signals from `port_directions` when available so
          // that primitive I/O appears in signal search results.
          final isCellComputed = cellType.startsWith(r'$');
          final portDirections =
              cellData['port_directions'] as Map<String, dynamic>?;
          final connections = cellData['connections'] as Map<String, dynamic>?;
          final portWidths = cellData['port_widths'] as Map<String, dynamic>?;
          final cellSignals = <SignalOccurrence>[
            if (portDirections != null)
              ...portDirections.entries.indexed.map((pEntry) {
                final (pIdx, kv) = pEntry;
                final pName = kv.key;
                final pDir = kv.value.toString();
                final bits = (connections?[pName] as List?)?.length ??
                    (portWidths?[pName] as int?) ??
                    1;
                return SignalOccurrence(
                  name: pName,
                  direction: pDir,
                  width: bits,
                  isComputed: isCellComputed,
                  portIndex: pIdx,
                );
              }),
          ];

          final instNode = HierarchyOccurrence(
            name: cellName,
            definition: cellType,
            isPrimitive: true,
            signals: cellSignals,
          );
          childNodes.add(instNode);
        }
      }
    }

    // Create the occurrence with children and signals embedded
    return HierarchyOccurrence(
      name: name,
      definition: definition,
      signals: signalsList,
      children: childNodes,
    );
  }
}
