// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_data_source.dart
// Abstract interface for tree hierarchy data sources.
// Enables switching between DTD/VM connection and loopback modes.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

/// Abstract interface for obtaining module tree hierarchy data.
///
/// This enables rapid development without needing a separate debugging session.
abstract class TreeDataSource {
  /// Whether this data source is currently connected/ready.
  bool get isConnected;

  /// Human-readable description of the data source mode.
  String get modeDescription;

  /// Get the cached schematic JSON from the last eval/refresh.
  /// Returns null if no schematic data is available or hasn't been loaded yet.
  Map<String, dynamic>? getSchematicJson();

  /// Evaluate and return the module tree hierarchy.
  /// Returns null if no tree is available.
  Future<TreeModel?> evalModuleTree();

  /// Refresh and return the updated module tree.
  Future<TreeModel?> refreshModuleTree();

  /// Fetch the full schematic JSON for a single module definition.
  ///
  /// Used for incremental loading: after the initial hierarchy-slim load,
  /// callers request full connectivity for individual modules as the user
  /// expands them in the schematic viewer.
  ///
  /// Returns a JSON map `{"DefinitionName": { ports, cells, netnames }}`
  /// or `null` if the module is not found or incremental data is unavailable.
  Future<Map<String, dynamic>?> fetchModuleSchematic(String definitionName);

  /// Dispose any resources held by this data source.
  Future<void> dispose();
}
