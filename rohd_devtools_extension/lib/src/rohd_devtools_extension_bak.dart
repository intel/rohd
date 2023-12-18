// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// import 'package:devtools_app/devtools_app.dart';
import 'dart:async';
import 'dart:convert';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/rohd_appbar.dart';

class RohdDevToolsExtension extends StatelessWidget {
  const RohdDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdExtensionHomePage(),
    );
  }
}

class RohdExtensionHomePage extends StatefulWidget {
  const RohdExtensionHomePage({super.key});

  @override
  State<RohdExtensionHomePage> createState() => _RohdExtensionHomePageState();
}

class _RohdExtensionHomePageState extends State<RohdExtensionHomePage> {
  String? message, inputSearchTerm, outputSearchTerm, treeSearchTerm;

  late final EvalOnDartLibrary rohdControllerEval;
  late final Disposable evalDisposable;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  late Future<TreeModel> futureModuleTree;
  late TreeModel? selectedModule = null;

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
    futureModuleTree = evalModuleTree();
  }

  @override
  void dispose() {
    rohdControllerEval.dispose();
    evalDisposable.dispose();
    super.dispose();
  }

  Future<void> _initEval() async {
    await serviceManager.onServiceAvailable;
  }

  Map<String, dynamic> filterSignals(
      Map<String, dynamic> signals, String searchTerm) {
    Map<String, dynamic> filtered = {};

    signals.forEach((key, value) {
      if (key.toLowerCase().contains(searchTerm.toLowerCase())) {
        filtered[key] = value;
      }
    });

    return filtered;
  }

  void refreshModuleTree() {
    setState(() {
      futureModuleTree = rohdControllerEval
          .evalInstance('ModuleTree.instance.hierarchyJSON',
              isAlive: evalDisposable)
          .then((treeInstance) => TreeModel.fromJson(
              jsonDecode(treeInstance.valueAsString ?? "{}")));
    });
  }

  Future<TreeModel> evalModuleTree() async {
    final treeInstance = await rohdControllerEval.evalInstance(
        'ModuleTree.instance.hierarchyJSON',
        isAlive: evalDisposable);

    return TreeModel.fromJson(jsonDecode(treeInstance.valueAsString ?? ""));
  }

  bool _isNodeOrDescendentMatching(TreeModel module) {
    if (module.name.toLowerCase().contains(treeSearchTerm!.toLowerCase())) {
      return true;
    }

    for (TreeModel childModule in module.subModules) {
      if (_isNodeOrDescendentMatching(childModule)) {
        return true;
      }
    }
    return false;
  }

  TreeNode? buildNode(TreeModel module) {
    // If there's a search term, ensure that either this node or a descendant node matches it.
    if (treeSearchTerm != null && !_isNodeOrDescendentMatching(module)) {
      return null;
    }

    // Build children recursively
    List<TreeNode> childrenNodes = buildChildrenNodes(module);

    return TreeNode(
      content: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              selectedModule = module;
            });
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

  List<TreeNode> buildChildrenNodes(TreeModel treeModule) {
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

  String getSignals(String moduleName) {
    return '';
  }

  Widget genModuleTree() {
    return FutureBuilder<TreeModel>(
      future: futureModuleTree,
      builder: (BuildContext context, AsyncSnapshot<TreeModel> snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            List<TreeNode> nodes = [];
            var root = buildNode(snapshot.data!);
            if (root != null) {
              nodes.add(root);
            }
            return TreeView(nodes: nodes);
          }
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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

  List<TableRow> generateSignalsRow(TreeModel module) {
    List<TableRow> rows = [];

    // Filter signals
    var inputSignals = filterSignals(module.inputs, inputSearchTerm ?? '');
    var outputSignals = filterSignals(module.outputs, outputSearchTerm ?? '');

    // Add Inputs
    for (var entry in inputSignals.entries) {
      rows.add(TableRow(children: <Widget>[
        SizedBox(
          height: 32,
          child: Center(
            child: Text(entry.key),
          ),
        ),
        const SizedBox(
          height: 32,
          child: Center(
            child: Text('Input'),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text('${(entry.value as Map)['value']}'),
          ),
        ),
      ]));
    }

    // Add Outputs
    for (var entry in outputSignals.entries) {
      rows.add(TableRow(children: <Widget>[
        SizedBox(
          height: 32,
          child: Center(
            child: Text(entry.key), // Signal Name
          ),
        ),
        const SizedBox(
          height: 32,
          child: Center(
            child: Text('Output'), // Signal Direction
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text('${(entry.value as Map)['value']}'), // Signal Value
          ),
        ),
      ]));
    }

    return rows;
  }

  Widget _detailCardWidgets(TreeModel? module) {
    if (module == null) {
      return const Text('No module selected');
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
                          'Signal Name',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Signal Direction',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          'Signal Value',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ...generateSignalsRow(module),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget renderIO(Map<String, dynamic> ioModule) {
    return Column(
      children: ioModule.entries
          .map<Widget>(
            (entry) => Text('${entry.key}: ${(entry.value as Map)['value']}'),
          )
          .toList(),
    );
  }

  Widget buildSubModules(TreeModel module) {
    if (module.subModules.isEmpty) {
      return const SizedBox.shrink(); // Return empty box if no submodules.
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: module.subModules.map<Widget>((subModule) {
        return Text('Submodule Name: ${subModule.name}');
      }).toList(),
    );
  }
}
