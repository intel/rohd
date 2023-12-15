// Will contain logic related to tree operations
import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';

class TreeService {
  final EvalOnDartLibrary rohdControllerEval;
  final Disposable evalDisposable;

  TreeService(this.rohdControllerEval, this.evalDisposable);

  Future<TreeModule> evalModuleTree() async {
    final treeInstance = await rohdControllerEval.evalInstance(
        'ModuleTree.instance.hierarchyJSON',
        isAlive: evalDisposable);

    return TreeModule.fromJson(jsonDecode(treeInstance.valueAsString ?? ""));
  }

  bool isNodeOrDescendentMatching(TreeModule module, String? treeSearchTerm) {
    if (module.name.toLowerCase().contains(treeSearchTerm!.toLowerCase())) {
      return true;
    }

    for (TreeModule childModule in module.subModules) {
      if (isNodeOrDescendentMatching(childModule, treeSearchTerm)) {
        return true;
      }
    }
    return false;
  }

  Future<TreeModule> refreshModuleTree() {
    return rohdControllerEval
        .evalInstance('ModuleTree.instance.hierarchyJSON',
            isAlive: evalDisposable)
        .then((treeInstance) => TreeModule.fromJson(
            jsonDecode(treeInstance.valueAsString ?? "{}")));
  }
}
