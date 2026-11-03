// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_process_tree_data_source.dart
// Tree data source that calls ModuleServices.instance directly (in-process).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart'
    show ModuleServices, NetlistService, TraceService;
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_data_source.dart';

/// [TreeDataSource] that calls [ModuleServices] directly in the same process.
///
/// This replaces the VM-service path for loopback/demo mode: instead of
/// sending JSON over WebSocket → evaluate() → parse, it calls the ROHD
/// diagnostics singletons directly.
///
/// Requires that the ROHD module has been built and waveform dumping has been
/// initialized so the ROHD services are available.
class InProcessTreeDataSource implements TreeDataSource {
  /// Human-readable name for this data source.
  final String name;

  bool _isRunning = true;

  /// Cached schematic JSON from the last load.
  Map<String, dynamic>? _cachedSchematicJson;

  /// Creates an in-process tree data source.
  InProcessTreeDataSource({this.name = 'In-Process'});

  @override
  bool get isConnected => _isRunning;

  @override
  String get modeDescription => 'In-Process ($name)';

  @override
  Map<String, dynamic>? getSchematicJson() => _cachedSchematicJson;

  @override
  Future<TreeModel?> evalModuleTree() async {
    if (!_isRunning) {
      return null;
    }

    try {
      // Read the unified netlist directly — same as what
      // VmServiceTreeDataSource does via evaluate().
      final jsonString = NetlistService.current?.slimJson ??
          ModuleServices.instance.hierarchyJson;
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

      if (jsonMap['status'] == 'fail') {
        debugPrint('[InProcessTree] ModuleServices returned status=fail');
        return null;
      }

      final designData = DesignDataAdapter.parseJson(jsonMap);
      _cachedSchematicJson = designData.schematicJson;

      debugPrint(
        '[InProcessTree] Loaded tree: '
        '${designData.hierarchy.root.name} '
        '(schematic: ${_cachedSchematicJson != null})',
      );

      return designData.hierarchy.root;
    } on Object catch (error, stackTrace) {
      debugPrint('[InProcessTree] evalModuleTree error: $error\n$stackTrace');
      return null;
    }
  }

  @override
  Future<TreeModel?> refreshModuleTree() {
    _cachedSchematicJson = null;
    return evalModuleTree();
  }

  @override
  Future<Map<String, dynamic>?> fetchModuleSchematic(
    String definitionName,
  ) async {
    if (!_isRunning) {
      return null;
    }

    try {
      // Read the per-module netlist directly — same as
      // VmServiceTreeDataSource's incremental loading.
      final jsonString = NetlistService.current?.moduleJson(definitionName);
      if (jsonString == null) {
        return null;
      }

      var result = jsonDecode(jsonString) as Map<String, dynamic>;

      if (result.containsKey('status')) {
        debugPrint(
          '[InProcessTree] fetchModuleSchematic: '
          '"$definitionName" not found',
        );
        return null;
      }

      // New format wraps module data under a 'modules' key.
      if (result.containsKey('modules') &&
          !result.containsKey(definitionName)) {
        result = result['modules'] as Map<String, dynamic>;
      }

      debugPrint(
        '[InProcessTree] fetchModuleSchematic: '
        '"$definitionName" → ${jsonEncode(result).length} bytes',
      );

      // Also update the cached schematic with the expanded module data.
      if (_cachedSchematicJson != null) {
        final modules =
            _cachedSchematicJson!['modules'] as Map<String, dynamic>?;
        if (modules != null && result.containsKey(definitionName)) {
          modules[definitionName] = result[definitionName];
        }
      }

      return result;
    } on Exception catch (e) {
      debugPrint('[InProcessTree] fetchModuleSchematic error: $e');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _isRunning = false;
    _cachedSchematicJson = null;
  }

  // ─── FLC (source cross-probe) ──────────────────────────────────────

  /// Fetch per-module FLC JSON by calling `ModuleServices` directly.
  Future<Map<String, dynamic>?> fetchModuleFlc(String definitionName) async {
    if (!_isRunning) {
      return null;
    }
    try {
      final jsonString = TraceService.current?.flcModuleJson(definitionName) ??
          '{"status":"unavailable"}';
      final result = jsonDecode(jsonString) as Map<String, dynamic>;
      if (result.containsKey('status') && result['status'] != 'ok') {
        debugPrint(
          '[InProcessTree] fetchModuleFlc: '
          '"$definitionName" → ${result['status']}',
        );
        return null;
      }
      return result;
    } on Exception catch (e) {
      debugPrint('[InProcessTree] fetchModuleFlc error: $e');
      return null;
    }
  }

  /// Fetch the full FLC hierarchy JSON by calling `ModuleServices` directly.
  Future<Map<String, dynamic>?> fetchFlcHierarchy() async {
    if (!_isRunning) {
      return null;
    }
    try {
      final jsonString =
          TraceService.current?.flcJson ?? '{"status":"unavailable"}';
      final result = jsonDecode(jsonString) as Map<String, dynamic>;
      if (result.containsKey('status') && result['status'] != 'ok') {
        debugPrint('[InProcessTree] fetchFlcHierarchy: ${result['status']}');
        return null;
      }
      return result;
    } on Exception catch (e) {
      debugPrint('[InProcessTree] fetchFlcHierarchy error: $e');
      return null;
    }
  }

  /// Clear upstream FLC caches (no-op for in-process).
  void clearFlcCache() {
    // Nothing to clear — ModuleServices always returns fresh data.
  }

  /// Returns the FLC file path by delegating to `ModuleServices.instance`.
  ///
  /// In in-process mode the running ROHD app is in the same isolate, so we can
  /// call `TraceService.current?.writtenPath ?? '{"status":"unavailable"}'`
  /// directly.
  Future<String?> fetchFlcFilePath() async {
    if (!_isRunning) {
      return null;
    }
    try {
      final path =
          TraceService.current?.writtenPath ?? '{"status":"unavailable"}';
      // The getter returns a JSON error string on failure.
      if (path.startsWith('{')) {
        debugPrint('[InProcessTree] fetchFlcFilePath: unavailable: $path');
        return null;
      }
      debugPrint('[InProcessTree] fetchFlcFilePath: $path');
      return path;
    } on Exception catch (e) {
      debugPrint('[InProcessTree] fetchFlcFilePath error: $e');
      return null;
    }
  }
}
