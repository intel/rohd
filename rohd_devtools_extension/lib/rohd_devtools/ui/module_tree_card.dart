// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_card.dart
// UI for module tree card.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';

import 'package:rohd_devtools_extension/rohd_devtools/cubit/selected_module_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/tree_search_term_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';

class ModuleTreeCard extends StatefulWidget {
  final TreeModel futureModuleTree;
  const ModuleTreeCard({
    super.key,
    required this.futureModuleTree,
  });

  @override
  State<ModuleTreeCard> createState() => _ModuleTreeCardState();
}

class _ModuleTreeCardState extends State<ModuleTreeCard> {
  _ModuleTreeCardState();

  @override
  Widget build(BuildContext context) {
    return genModuleTree(
      moduleTree: widget.futureModuleTree,
    );
  }

  TreeNode? buildNode(TreeModel module) {
    final treeSearchTerm = context.watch<TreeSearchTermCubit>().state;
    // If there's a search term, ensure that either this node or a descendant node matches it.
    if (treeSearchTerm != null &&
        !TreeService.isNodeOrDescendentMatching(module, treeSearchTerm)) {
      return null;
    }

    // Build children recursively
    List<TreeNode> childrenNodes = buildChildrenNodes(module);

    return TreeNode(
      content: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            context.read<SelectedModuleCubit>().setModule(module);
          },
          child: getNodeContent(module),
        ),
      ),
      children: childrenNodes,
    );
  }

  Widget getNodeContent(TreeModel module) {
    return Row(
      children: [
        const Icon(Icons.memory),
        const SizedBox(width: 2.0),
        Text(module.name),
      ],
    );
  }

  List<TreeNode> buildChildrenNodes(
    TreeModel treeModule,
  ) {
    List<TreeNode?> childrenNodes = [];
    List<dynamic> subModules = treeModule.subModules;
    if (subModules.isNotEmpty) {
      for (var module in subModules) {
        TreeNode? node = buildNode(module);
        if (node != null) {
          childrenNodes.add(node);
        }
      }
    }
    return childrenNodes
        .where((node) => node != null)
        .toList()
        .cast<TreeNode>();
  }

  TreeNode? buildTreeFromModule(TreeModel node) {
    return buildNode(node);
  }

  Widget genModuleTree({
    required TreeModel moduleTree,
  }) {
    var root = buildNode(moduleTree);
    if (root != null) {
      return TreeView(nodes: [root]);
    } else {
      return const Text('No data');
    }
  }
}
