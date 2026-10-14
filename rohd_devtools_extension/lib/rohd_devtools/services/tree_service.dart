// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_service.dart
// Services for tree logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:vm_service/vm_service.dart';

/// Service helpers for evaluating and filtering the ROHD module tree.
class TreeService {
  /// Expression for retrieving the module hierarchy JSON.
  static const _hierarchyExpression = 'ModuleTree.instance.hierarchyJson';

  /// Eval wrapper for accessing ROHD code in the target isolate.
  final EvalOnDartLibrary rohdControllerEval;

  /// Disposable token used to keep the eval alive.
  final Disposable evalDisposable;

  /// Optional VM service for source-line lookups (cross-probe).
  final VmService? vmService;

  /// Optional isolate ID used with [vmService].
  final String? isolateId;

  /// Creates a tree service around the given eval wrapper.
  TreeService(this.rohdControllerEval, this.evalDisposable,
      {this.vmService, this.isolateId});

  /// Evaluates the module tree from the ROHD service.
  Future<TreeModel?> evalModuleTree() async {
    final payload = await _evalTreePayload();
    if (payload == null || payload.isEmpty) {
      debugPrint('[TreeService] evalModuleTree failed: empty payload');
      return null;
    }

    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      debugPrint('[TreeService] evalModuleTree failed: unexpected payload type '
          '${decoded.runtimeType}');
      return null;
    }

    final treeObj = decoded;

    if (treeObj['status'] == 'fail' || treeObj['status'] == 'unavailable') {
      final message =
          treeObj['message'] ?? treeObj['reason'] ?? treeObj['error'];
      debugPrint('[TreeService] evalModuleTree failed: $message');
      return null;
    }

    return TreeModel.fromJson(treeObj);
  }

  Future<String?> _evalTreePayload() async {
    try {
      final treeInstance = await rohdControllerEval
          .evalInstance(_hierarchyExpression, isAlive: evalDisposable);
      return treeInstance.valueAsString;
    } on Exception catch (e) {
      debugPrint('[TreeService] Eval failed for "$_hierarchyExpression": $e');
      return null;
    }
  }

  /// Returns whether the current module or any descendant matches the search.
  static bool isNodeOrDescendentMatching(
      TreeModel module, String? treeSearchTerm) {
    if (module.name.toLowerCase().contains(treeSearchTerm!.toLowerCase())) {
      return true;
    }

    for (final childModule in module.subModules) {
      if (isNodeOrDescendentMatching(childModule, treeSearchTerm)) {
        return true;
      }
    }
    return false;
  }

  /// Refreshes the module tree from the ROHD service.
  Future<TreeModel> refreshModuleTree() async {
    final treeModel = await evalModuleTree();
    if (treeModel == null) {
      throw StateError('Failed to refresh module tree.');
    }
    return treeModel;
  }
}
