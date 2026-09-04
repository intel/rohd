// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standalone_tree_service.dart
// Tree service for standalone (non-web) builds using vm_service directly.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:vm_service/vm_service.dart';

/// Tree service that uses VmService directly without devtools_app_shared.
class StandaloneTreeService {
  /// The connected VM service.
  final VmService vmService;

  /// The isolate ID of the ROHD application.
  final String isolateId;

  static const _unifiedFunc = 'NetlistService.current?.slimJson ?? '
      'ModuleServices.instance.hierarchyJson';

  /// Cached schematic JSON from the last eval/refresh.
  Map<String, dynamic>? _cachedSchematicJson;

  /// Get the cached schematic JSON from the last eval/refresh.
  Map<String, dynamic>? getSchematicJson() => _cachedSchematicJson;

  /// Creates a [StandaloneTreeService] with the given VM service and isolate
  /// ID.
  StandaloneTreeService({required this.vmService, required this.isolateId});

  /// Evaluate the module tree from the connected ROHD application.
  Future<TreeModel?> evalModuleTree() async {
    try {
      // Find the ROHD library in the isolate
      final isolate = await vmService.getIsolate(isolateId);
      final libraries = isolate.libraries ?? [];

      Library? rohdLibrary;
      for (final libRef in libraries) {
        final uri = libRef.uri;
        if (uri != null &&
            uri.contains('rohd') &&
            uri.contains('inspector_service')) {
          rohdLibrary =
              await vmService.getObject(isolateId, libRef.id!) as Library;
          break;
        }
      }

      if (rohdLibrary == null) {
        // Try to find it by evaluating on the isolate
        return await _evalOnIsolate();
      }

      // Evaluate unified format (contains both hierarchy and schematic)
      final result = await vmService.evaluate(
        isolateId,
        rohdLibrary.id!,
        _unifiedFunc,
      );
      return _parseResult(result);
    } on Exception {
      final tree = await _evalOnIsolate();
      return tree;
    }
  }

  /// Fallback: try to evaluate on the isolate directly
  Future<TreeModel?> _evalOnIsolate() async {
    try {
      // Get the root library and evaluate
      final isolate = await vmService.getIsolate(isolateId);
      final rootLibRef = isolate.rootLib;

      if (rootLibRef == null) {
        return null;
      }

      // Evaluate unified format
      final result = await vmService.evaluate(
        isolateId,
        rootLibRef.id!,
        '(() { '
        'try { '
        'return NetlistService.current?.slimJson ?? '
        'ModuleServices.instance.hierarchyJson; '
        '} catch (e) { '
        'return \'{"status": "fail", "error": "\$e"}\'; '
        '} '
        '})()',
      );

      return _parseResult(result);
    } on Exception {
      return null;
    }
  }

  TreeModel? _parseResult(Response result) {
    if (result is InstanceRef) {
      final valueStr = result.valueAsString;
      if (valueStr == null) {
        return null;
      }

      try {
        final treeObj = jsonDecode(valueStr) as Map<String, dynamic>;

        if (treeObj['status'] == 'fail') {
          return null;
        }

        // Use DesignDataAdapter for consistent parsing across all services
        final designData = DesignDataAdapter.parseJson(treeObj);
        _cachedSchematicJson = designData.schematicJson;
        return designData.hierarchy.root;
      } on Exception {
        return null;
      }
    } else if (result is ErrorRef) {
      return null;
    } else {
      return null;
    }
  }

  /// Refresh the module tree
  Future<TreeModel?> refreshModuleTree() => evalModuleTree();
}
