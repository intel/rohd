// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_card.dart
// UI for module tree card.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Widget that displays the module tree in a card.
class ModuleTreeCard extends StatefulWidget {
  /// The module tree to display.
  final TreeModel futureModuleTree;

  /// Creates a [ModuleTreeCard] with the given module tree.
  const ModuleTreeCard({required this.futureModuleTree, super.key});

  @override
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
  _ModuleTreeCardState();

  @override
  // Use BlocBuilder to efficiently rebuild only when state changes
  Widget build(BuildContext context) =>
      BlocBuilder<TreeSearchTermCubit, String?>(
        builder: (context, treeSearchTerm) =>
            BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
          buildWhen: (prev, curr) {
            final prevSel =
                prev is HierarchyLoaded ? prev.selectedModule : null;
            final currSel =
                curr is HierarchyLoaded ? curr.selectedModule : null;
            return prevSel != currSel;
          },
          builder: (context, hierarchyState) {
            final selectedModule = hierarchyState is HierarchyLoaded
                ? hierarchyState.selectedModule
                : null;

            return _ModuleTreeView(
              moduleTree: widget.futureModuleTree,
              treeSearchTerm: treeSearchTerm,
              selectedModule: selectedModule,
              onModuleSelected: (module) {
                context.read<DevToolsHierarchyCubit>().selectModule(module);
              },
            );
          },
        ),
      );
}

/// Stateful widget that builds the tree and manages tree controller.
/// Manages the tree controller to keep nodes collapsed by default.
class _ModuleTreeView extends StatefulWidget {
  final TreeModel moduleTree;
  final String? treeSearchTerm;
  final TreeModel? selectedModule;
  final ValueChanged<TreeModel> onModuleSelected;

  const _ModuleTreeView({
    required this.moduleTree,
    required this.treeSearchTerm,
    required this.selectedModule,
    required this.onModuleSelected,
  });

  @override
  State<_ModuleTreeView> createState() => _ModuleTreeViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel>('moduleTree', moduleTree))
      ..add(StringProperty('treeSearchTerm', treeSearchTerm))
      ..add(DiagnosticsProperty<TreeModel?>('selectedModule', selectedModule))
      ..add(
        ObjectFlagProperty<ValueChanged<TreeModel>>.has(
          'onModuleSelected',
          onModuleSelected,
        ),
      );
  }
}

class _ModuleTreeViewState extends State<_ModuleTreeView> {
  late TreeController _treeController;

  @override
  void initState() {
    super.initState();
    // Create a tree controller with all nodes collapsed by default
    _treeController = TreeController(allNodesExpanded: false);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel>('moduleTree', widget.moduleTree))
      ..add(StringProperty('treeSearchTerm', widget.treeSearchTerm))
      ..add(
        DiagnosticsProperty<TreeModel?>(
          'selectedModule',
          widget.selectedModule,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<TreeModel>>.has(
          'onModuleSelected',
          widget.onModuleSelected,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final root = _buildNode(widget.moduleTree);
    if (root != null) {
      return TreeView(nodes: [root], treeController: _treeController);
    } else {
      return const Text('No data');
    }
  }

  TreeNode? _buildNode(TreeModel module) {
    // If there's a search term, ensure that either this node or a descendant
    // node matches it.
    if (widget.treeSearchTerm != null &&
        !HierarchyService.isOccurrenceMatching(module, widget.treeSearchTerm)) {
      return null;
    }

    // Build children recursively
    final childrenNodes = _buildChildrenNodes(module);

    return TreeNode(
      key: ObjectKey(module),
      content: RepaintBoundary(
        child: GestureDetector(
          onTap: () => widget.onModuleSelected(module),
          child: _NodeContent(
            module: module,
            isSelected: widget.selectedModule == module,
          ),
        ),
      ),
      children: childrenNodes,
    );
  }

  List<TreeNode> _buildChildrenNodes(TreeModel treeModule) {
    final childrenNodes = <TreeNode>[];
    final subModules = treeModule.children;
    for (final module in subModules) {
      // Skip primitive cells (gates, flip-flops, operators, etc.)
      // — these are implementation details, not navigable hierarchy.
      if (module.isPrimitiveCell) {
        continue;
      }
      // Keep leaf modules — they may have signals but no sub-modules,
      // and users need to select them to view those signals.
      // Skip internal struct_assign blocks — these are generated
      // structural nodes that clutter the tree.
      if (module.name.contains('struct_assign')) {
        continue;
      }
      final node = _buildNode(module);
      if (node != null) {
        childrenNodes.add(node);
      }
    }
    return childrenNodes;
  }
}

/// Stateless widget for node content to avoid rebuilds.
class _NodeContent extends StatelessWidget {
  final TreeModel module;
  final bool isSelected;

  const _NodeContent({required this.module, required this.isSelected});

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel>('module', module))
      ..add(
        FlagProperty(
          'isSelected',
          value: isSelected,
          ifTrue: 'selected',
          ifFalse: 'not selected',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Keep instance names for hierarchy nodes, but show the root module
    // by definition name so the tree's top identity matches synthesis.
    // This avoids surfacing synthetic instance defaults (e.g.
    // `floatingpoint_adder_singlepath`) as the design's top name.
    final isRoot = module.parent == null;
    final displayName =
        isRoot ? (module.definition ?? module.name) : module.name;

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
              Icon(
                Icons.memory,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 2),
              Text(
                displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
