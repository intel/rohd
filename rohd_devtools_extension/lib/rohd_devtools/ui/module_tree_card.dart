// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_card.dart
// UI for module tree card.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';

import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';

/// Displays the module tree for the currently loaded ROHD model.
class ModuleTreeCard extends StatefulWidget {
  /// The root module to render as the tree.
  final TreeModel futureModuleTree;

  /// Creates a module tree card for the provided module tree.
  const ModuleTreeCard({
    required this.futureModuleTree,
    super.key,
  });

  @override

  /// Creates the mutable state for [ModuleTreeCard].
  State<ModuleTreeCard> createState() => _ModuleTreeCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<TreeModel>('futureModuleTree', futureModuleTree),
    );
  }
}

class _ModuleTreeCardState extends State<ModuleTreeCard> {
  /// Creates the module tree card state.
  _ModuleTreeCardState();

  @override

  /// Builds the module tree widget.
  Widget build(BuildContext context) => genModuleTree(
        moduleTree: widget.futureModuleTree,
      );

  /// Builds a tree node for [module], returning null if it is filtered out.
  TreeNode? buildNode(TreeModel module) {
    final treeSearchTerm = context.watch<TreeSearchTermCubit>().state;
    // If there's a search term, ensure that either this node or a
    // descendant node matches it.
    if (treeSearchTerm != null &&
        !TreeService.isNodeOrDescendentMatching(module, treeSearchTerm)) {
      return null;
    }

    // Build children recursively
    final childrenNodes = buildChildrenNodes(module);

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

  /// Builds the visible text and icon for a tree node.
  Widget getNodeContent(TreeModel module) {
    final selectedModule = context.watch<SelectedModuleCubit>().state;
    final colorScheme = Theme.of(context).colorScheme;

    // Check if the current module is the selected module
    final isSelected = selectedModule is SelectedModuleLoaded &&
        selectedModule.module == module;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            children: [
              Icon(Icons.memory, color: colorScheme.onSurface),
              const SizedBox(width: 2),
              Text(
                module.name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color:
                      isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds child tree nodes for the given module.
  List<TreeNode> buildChildrenNodes(
    TreeModel treeModule,
  ) {
    final childrenNodes = <TreeNode>[];
    final subModules = treeModule.subModules;
    if (subModules.isNotEmpty) {
      for (final module in subModules) {
        final node = buildNode(module);
        if (node != null) {
          childrenNodes.add(node);
        }
      }
    }
    return childrenNodes;
  }

  /// Returns a tree node wrapper for the provided module.
  TreeNode? buildTreeFromModule(TreeModel node) => buildNode(node);

  /// Builds the full tree view widget for [moduleTree].
  Widget genModuleTree({
    required TreeModel moduleTree,
  }) {
    final root = buildNode(moduleTree);
    if (root != null) {
      return TreeView(nodes: [root]);
    }
    return const Text('No data');
  }
}
