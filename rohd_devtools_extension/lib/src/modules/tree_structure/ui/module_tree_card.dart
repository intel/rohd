import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_search_term_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/tree_service.dart';

class ModuleTreeCard extends ConsumerStatefulWidget {
  final AsyncValue<TreeModel> futureModuleTree;
  const ModuleTreeCard({
    super.key,
    required this.futureModuleTree,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ModuleTreeCardState();
}

class _ModuleTreeCardState extends ConsumerState<ModuleTreeCard> {
  _ModuleTreeCardState();

  @override
  Widget build(BuildContext context) {
    return genModuleTree(
      moduleTreeAsyncValue: widget.futureModuleTree,
    );
  }

  TreeNode? buildNode(TreeModel module) {
    final TreeService treeService = ref.read(treeServiceProvider);
    final treeSearchTerm = ref.watch(treeSearchTermProvider);
    // If there's a search term, ensure that either this node or a descendant node matches it.
    if (treeSearchTerm != null &&
        !treeService.isNodeOrDescendentMatching(module, treeSearchTerm)) {
      return null;
    }

    // Build children recursively
    List<TreeNode> childrenNodes = buildChildrenNodes(module);

    return TreeNode(
      content: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            ref.read(selectedModuleProvider.notifier).setModule(module);
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
    required AsyncValue<TreeModel> moduleTreeAsyncValue,
  }) {
    return moduleTreeAsyncValue.when(
      data: (TreeModel data) {
        var root = buildNode(data);
        if (root != null) {
          return Align(
            alignment: Alignment.topLeft,
            child: TreeView(nodes: [root]),
          );
        } else {
          return const Text('No data');
        }
      },
      error: (error, stackTrace) => Text('Error: $error'),
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
