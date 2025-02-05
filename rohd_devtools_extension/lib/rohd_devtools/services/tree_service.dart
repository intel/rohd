// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_services.dart
// Services for tree logic.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

class TreeService {
  final invokeFunc = 'ModuleTree.instance.hierarchyJSON';
  final EvalOnDartLibrary rohdControllerEval;
  final Disposable evalDisposable;

  TreeService(this.rohdControllerEval, this.evalDisposable);

  Future<TreeModel?> evalModuleTree() async {
    final treeInstance = await rohdControllerEval.evalInstance(
      invokeFunc,
      isAlive: evalDisposable,
    );

    final treeObj = jsonDecode(treeInstance.valueAsString ?? '') as Map;

    if (treeObj['status'] == 'fail') {
      print('error');

      return null;
    } else {
      return TreeModel.fromJson(jsonDecode(treeInstance.valueAsString ?? ""));
    }
  }

  static bool isNodeOrDescendentMatching(
      TreeModel module, String? treeSearchTerm) {
    if (module.name.toLowerCase().contains(treeSearchTerm!.toLowerCase())) {
      return true;
    }

    for (TreeModel childModule in module.subModules) {
      if (isNodeOrDescendentMatching(childModule, treeSearchTerm)) {
        return true;
      }
    }
    return false;
  }

  Future<TreeModel> refreshModuleTree() {
    return rohdControllerEval
        .evalInstance(invokeFunc, isAlive: evalDisposable)
        .then((treeInstance) =>
            TreeModel.fromJson(jsonDecode(treeInstance.valueAsString ?? "{}")));
  }
}
