// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_data_adapter.dart
// Unified adapter for parsing design data in any supported format.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Enum representing the detected format of design data.
enum DesignDataFormat {
  /// Legacy inspector tree format: `{name, inputs, outputs, subModules}`.
  legacyModuleTree,

  /// Yosys netlist format: {modules: {...}}
  netlistSchematic,

  /// Unified format: {netlist: {...}} or {schematic: {...}}
  unified,
}

/// Result of parsing design data.
///
/// Contains the hierarchy service (always present) and optionally
/// schematic data if the input format included connectivity information.
class DesignData {
  /// The hierarchy service for module tree navigation.
  final HierarchyService hierarchy;

  /// Raw schematic data in Yosys format (if available).
  /// This can be passed to NetlistSchematicAdapter for rendering.
  final Map<String, dynamic>? schematicJson;

  /// True if schematic data is available.
  bool get hasSchematic => schematicJson != null;

  /// The detected format of the original input.
  final DesignDataFormat format;

  /// Optional metadata from the input.
  final String? creator;

  /// Optional version from the input.
  final String? version;

  /// Creates a DesignData object with the given hierarchy, format, and optional
  /// schematic and metadata.
  DesignData({
    required this.hierarchy,
    required this.format,
    this.schematicJson,
    this.creator,
    this.version,
  });
}

/// Unified adapter that parses design data in netlist format.
///
/// Supported formats:
/// 1. **Legacy Module Tree** - `{name, inputs, outputs, subModules}`
/// 2. **Yosys Netlist** - `{modules: {...}}`
/// 3. **Unified** - `{netlist: {...}}` or `{schematic: {...}}`
///
/// Usage:
/// ```dart
/// final data = DesignDataAdapter.parse(jsonString);
/// final tree = data.hierarchy.root; // Always available
/// if (data.hasSchematic) {
///   final schematic = NetlistSchematicAdapter.fromJson(
///     jsonEncode(data.schematicJson),
///   );
/// }
/// ```
class DesignDataAdapter {
  DesignDataAdapter._();

  /// Parse design data from a JSON string.
  ///
  /// Automatically detects the format and returns a [DesignData] object
  /// containing the hierarchy and optional schematic data.
  static DesignData parse(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return parseJson(json);
  }

  /// Parse design data from a JSON map.
  ///
  /// Automatically detects the format and returns a [DesignData] object.
  static DesignData parseJson(Map<String, dynamic> json) {
    // Check for status: fail like real ROHD inspector service
    if (json['status'] == 'fail') {
      throw const FormatException('ROHD inspector reported failure');
    }

    final format = detectFormat(json);

    switch (format) {
      case DesignDataFormat.legacyModuleTree:
        return _parseLegacyModuleTree(json);

      case DesignDataFormat.netlistSchematic:
        return _parseNetlistSchematic(json);

      case DesignDataFormat.unified:
        return _parseUnified(json);
    }
  }

  /// Detect the format of the given JSON.
  static DesignDataFormat detectFormat(Map<String, dynamic> json) {
    // Legacy inspector format: a recursive module tree without connectivity.
    if (json.containsKey('name') && json.containsKey('subModules')) {
      return DesignDataFormat.legacyModuleTree;
    }

    // Unified format: has 'netlist' or 'schematic' wrapper key.
    if (json.containsKey('netlist') || json.containsKey('schematic')) {
      return DesignDataFormat.unified;
    }

    // Yosys format: has 'modules' key directly.
    if (json.containsKey('modules')) {
      return DesignDataFormat.netlistSchematic;
    }

    throw FormatException(
      'Unsupported design format: expected legacy module tree '
      '({name, subModules: ...}), netlist ({modules: ...}), or unified '
      '({netlist: ...}), got keys: ${json.keys.toList()}',
    );
  }

  /// Parse the hierarchy-only tree emitted by the legacy inspector service.
  ///
  /// This format has no cell or net connectivity, so schematic data remains
  /// null and schematic consumers can retain their existing unavailable state.
  static DesignData _parseLegacyModuleTree(Map<String, dynamic> json) {
    final root = _legacyOccurrence(json);
    return DesignData(
      hierarchy: BaseHierarchyAdapter.fromTree(root),
      format: DesignDataFormat.legacyModuleTree,
    );
  }

  static HierarchyOccurrence _legacyOccurrence(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Legacy module tree node has no name');
    }

    final signals = [
      ..._legacyPorts(json['inputs'], 'input'),
      ..._legacyPorts(json['outputs'], 'output'),
      ..._legacyPorts(json['inouts'], 'inout'),
    ];
    final rawChildren = json['subModules'];
    if (rawChildren is! List) {
      throw FormatException('Legacy module "$name" has invalid subModules');
    }

    return HierarchyOccurrence(
      name: name,
      definition: name,
      signals: signals,
      children: rawChildren.map((child) {
        if (child is! Map) {
          throw FormatException('Legacy module "$name" has invalid child');
        }
        return _legacyOccurrence(Map<String, dynamic>.from(child));
      }).toList(),
    );
  }

  static List<SignalOccurrence> _legacyPorts(
    Object? rawPorts,
    String direction,
  ) {
    if (rawPorts is! Map) {
      return const [];
    }

    return rawPorts.entries.indexed.map((entry) {
      final portIndex = entry.$1;
      final portName = entry.$2.key;
      final rawPort = entry.$2.value;
      final port = rawPort is Map<String, dynamic>
          ? rawPort
          : rawPort is Map
              ? Map<String, dynamic>.from(rawPort)
              : const <String, dynamic>{};
      final declaredName = port['name'];
      final width = port['width'];
      final value = port['value'];
      return SignalOccurrence(
        name: declaredName is String ? declaredName : portName.toString(),
        width: width is int && width > 0 ? width : 1,
        direction: direction,
        value: value is String ? value : null,
        portIndex: portIndex,
      );
    }).toList();
  }

  /// Parse netlist schematic format.
  ///
  /// This delegates the full hierarchy build to [NetlistHierarchyAdapter] from
  /// rohd_hierarchy, avoiding duplication of the netlist parsing logic.
  static DesignData _parseNetlistSchematic(Map<String, dynamic> json) {
    final modules = json['modules'] as Map<String, dynamic>?;
    if (modules == null || modules.isEmpty) {
      throw const FormatException('Yosys JSON contained no modules');
    }

    final service = NetlistHierarchyAdapter.fromMap(json);

    return DesignData(
      hierarchy: service,
      schematicJson: json,
      format: DesignDataFormat.netlistSchematic,
      creator: json['creator'] as String?,
    );
  }

  /// Parse unified format with netlist/schematic as the single source
  /// of truth.
  ///
  /// The `netlist` (or `schematic`) section contains the complete module
  /// hierarchy with ports, cells, and optionally connectivity.  The
  /// hierarchy tree is built from this netlist.
  static DesignData _parseUnified(Map<String, dynamic> json) {
    // Support both 'schematic' and 'netlist' keys for the netlist section.
    final schematicSection =
        (json['schematic'] ?? json['netlist']) as Map<String, dynamic>?;

    if (schematicSection == null) {
      throw const FormatException(
        'Unified format missing netlist/schematic section',
      );
    }

    // Normalize schematic section to {modules: {...}} format
    Map<String, dynamic> schematicJson;
    if (schematicSection.containsKey('modules')) {
      schematicJson = schematicSection;
    } else {
      schematicJson = {'modules': schematicSection};
    }

    final modulesMap = schematicJson['modules'] as Map<String, dynamic>?;
    if (modulesMap == null || modulesMap.isEmpty) {
      throw const FormatException(
        'Unified format: netlist/schematic has no modules',
      );
    }

    final rootName = schematicJson['rootInstanceName'] as String?;
    final service = NetlistHierarchyAdapter.fromMap(
      schematicJson,
      rootNameOverride: rootName,
    );

    return DesignData(
      hierarchy: service,
      schematicJson: schematicJson,
      format: DesignDataFormat.unified,
      version: json['version'] as String?,
      creator: json['creator'] as String?,
    );
  }
}
