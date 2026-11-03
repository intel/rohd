// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// static_json_tree_data_source.dart
// Tree data source backed by a pre-loaded JSON map (for file loading).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_data_source.dart';

/// [TreeDataSource] backed by a static JSON map.
///
/// Used when loading a design JSON file from disk. The JSON is parsed
/// once via [DesignDataAdapter] and the resulting hierarchy + schematic
/// are cached for the lifetime of this data source.
class StaticJsonTreeDataSource implements TreeDataSource {
  final Map<String, dynamic> _json;

  /// Human-readable name for this data source.
  final String name;

  TreeModel? _cachedTree;
  Map<String, dynamic>? _cachedSchematicJson;
  bool _isRunning = true;

  /// Creates a tree data source backed by static JSON.
  StaticJsonTreeDataSource(this._json, {this.name = 'Static JSON'});

  @override
  bool get isConnected => _isRunning;

  @override
  String get modeDescription => 'Static JSON ($name)';

  @override
  Map<String, dynamic>? getSchematicJson() => _cachedSchematicJson;

  @override
  Future<TreeModel?> evalModuleTree() async {
    if (!_isRunning) {
      return null;
    }
    if (_cachedTree != null) {
      return _cachedTree;
    }

    try {
      if (_json['status'] == 'fail') {
        return null;
      }

      final designData = DesignDataAdapter.parseJson(_json);
      _cachedSchematicJson = designData.schematicJson;
      _cachedTree = designData.hierarchy.root;

      debugPrint(
        '[StaticJsonTree] Loaded: ${_cachedTree?.name} '
        '(schematic: ${_cachedSchematicJson != null})',
      );
      return _cachedTree;
    } on Exception catch (e) {
      debugPrint('[StaticJsonTree] Parse error: $e');
      return null;
    }
  }

  @override
  Future<TreeModel?> refreshModuleTree() {
    _cachedTree = null;
    return evalModuleTree();
  }

  @override
  Future<Map<String, dynamic>?> fetchModuleSchematic(
    String definitionName,
  ) async {
    final modules = _cachedSchematicJson?['modules'] as Map<String, dynamic>?;
    if (modules == null) {
      return null;
    }

    final moduleData = modules[definitionName];
    if (moduleData == null) {
      return null;
    }

    return {
      'modules': {definitionName: moduleData},
    };
  }

  @override
  Future<void> dispose() async {
    _isRunning = false;
    _cachedTree = null;
    _cachedSchematicJson = null;
  }
}
