import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_services.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/tree_services.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/rohd_appbar.dart';

import '../providers/signal_service_provider.dart';

class RohdDevToolsExtension extends StatelessWidget {
  const RohdDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdExtensionHomePage(),
    );
  }
}

class RohdExtensionHomePage extends ConsumerStatefulWidget {
  const RohdExtensionHomePage({super.key});

  @override
  ConsumerState<RohdExtensionHomePage> createState() =>
      _RohdExtensionHomePageState();
}

class _RohdExtensionHomePageState extends ConsumerState<RohdExtensionHomePage> {
  String? message, inputSearchTerm, outputSearchTerm, treeSearchTerm;

  late final EvalOnDartLibrary rohdControllerEval;
  late final Disposable evalDisposable;

  // services
  late final TreeService treeService;
  late final SignalService signalService;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  late Future<TreeModule> futureModuleTree;
  // late TreeModule? selectedModule = null;

  @override
  void dispose() {
    rohdControllerEval.dispose();
    evalDisposable.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initEval();
    rohdControllerEval = EvalOnDartLibrary(
      'package:rohd/src/diagnostics/inspector_service.dart',
      serviceManager.service!,
      serviceManager: serviceManager,
    );

    evalDisposable = Disposable();

    treeService = ref.read(treeServiceProvider);
    signalService = ref.read(signalServiceProvider);

    futureModuleTree = treeService.evalModuleTree();
  }

  Future<void> _initEval() async {
    await serviceManager.onServiceAvailable;
  }

  void refreshModuleTree() {
    setState(() async {
      // Use treeService to refresh the module tree.
      futureModuleTree = treeService.refreshModuleTree();
    });
  }

  TreeNode? buildNode(TreeModule module) {
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
            // setState(() {
            //   selectedModule = module;
            // });
            ref.read(selectedModuleProvider.notifier).setModule(module);
          },
          child: getNodeContent(module),
        ),
      ),
      children: childrenNodes,
    );
  }

  Widget getNodeContent(TreeModule module) {
    return Row(
      children: [
        const Icon(Icons.memory),
        const SizedBox(width: 2.0),
        Text(module.name),
      ],
    );
  }

  List<TreeNode> buildChildrenNodes(TreeModule treeModule) {
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

  TreeNode? buildTreeFromModule(TreeModule node) {
    return buildNode(node);
  }

  String getSignals(String moduleName) {
    return '';
  }

  Widget genModuleTree() {
    return FutureBuilder<TreeModule>(
      future: futureModuleTree,
      builder: (BuildContext context, AsyncSnapshot<TreeModule> snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.waiting:
            return Center(child: CircularProgressIndicator());
          case ConnectionState.done:
            List<TreeNode> nodes = [];
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              var root = buildNode(snapshot.data!);
              if (root != null) {
                nodes.add(root);
              }
              return TreeView(nodes: nodes);
            }
          default:
            return Container();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedModule = ref.watch(selectedModuleProvider);
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: const RohdAppBar(),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          children: [
            SizedBox(
              width: screenSize.width / 3,
              height: screenSize.width / 2.6,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.account_tree),
                          const SizedBox(
                            width: 10,
                          ),
                          const Text('Module Tree'),
                          Expanded(
                              child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  onChanged: (value) {
                                    setState(() {
                                      treeSearchTerm = value;
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    labelText: "Search Tree",
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () => refreshModuleTree(),
                              ),
                            ],
                          )),
                        ],
                      ),
                    ),

                    // Module Tree render here
                    Container(
                      height: screenSize.width / 3,
                      width: screenSize.width / 3,
                      alignment: Alignment.topLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: genModuleTree(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              width: 20,
            ),
            SizedBox(
              width: screenSize.width / 3,
              height: screenSize.width / 2.6,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DetailsNavBar(),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: _detailCardWidgets(selectedModule),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCardWidgets(TreeModule? module) {
    if (module == null) {
      return Center(child: Text('No module selected'));
    }

    return Container(
      height: MediaQuery.of(context).size.height / 1.4,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) {
                        setState(() {
                          inputSearchTerm = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Search Input Signals",
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (value) {
                        setState(() {
                          outputSearchTerm = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Search Output Signals",
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Table(
              border: TableBorder.all(),
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                const TableRow(
                  children: <Widget>[
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Name',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Direction',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Value',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Width',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ...signalService.generateSignalsRow(
                  module,
                  inputSearchTerm,
                  outputSearchTerm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
