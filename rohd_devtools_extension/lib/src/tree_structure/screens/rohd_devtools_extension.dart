// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// import 'package:devtools_app/devtools_app.dart';
import 'dart:async';
import 'dart:convert';
import 'package:devtools_extensions/api.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import '../widgets/widgets.dart';

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
  String? message;

  late final EvalOnDartLibrary rohdControllerEval;
  late final Disposable evalDisposable;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  // Add a Future variable to hold the tree data
  late Future<String> futureModuleTree;

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

    // initialized the state of the module tree
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

  // Update evalModuleTree to be a state changing function.
  void refreshModuleTree() {
    setState(() {
      futureModuleTree = rohdControllerEval
          .evalInstance('ModuleTree.instance.hierarchyJSON',
              isAlive: evalDisposable)
          .then((treeInstance) =>
              treeInstance.valueAsString ?? _defaultEvalResponseText);
    });
  }

  Future<String> evalModuleTree() async {
    final treeInstance = await rohdControllerEval.evalInstance(
        'ModuleTree.instance.hierarchyJSON',
        isAlive: evalDisposable);

    return treeInstance.valueAsString ?? _defaultEvalResponseText;
  }

  TreeNode buildTreeFromJson(Map node) {
    TreeNode treeNode;

    String nodeName = '${node['name']}';
    List<TreeNode> children = [];

    Map inputs = node['inputs'];
    if (inputs.isNotEmpty) {
      for (var key in inputs.keys) {
        String inputContentText = "$key : ${inputs[key]['value']}";
        children.add(
          TreeNode(
            content: Row(children: <Widget>[
              Icon(
                Icons.east,
                color: Colors.blue.shade600,
              ),
              const SizedBox(
                width: 2,
              ),
              Text(inputContentText),
            ]),
          ),
        );
      }
    }

    Map outputs = node['outputs'];
    if (outputs.isNotEmpty) {
      for (var key in outputs.keys) {
        String outputContentText = "$key : ${outputs[key]['value']}";
        children.add(
          TreeNode(
            content: Row(children: <Widget>[
              Icon(
                Icons.west,
                color: Colors.green.shade600,
              ),
              const SizedBox(
                width: 2,
              ),
              Text(outputContentText),
            ]),
          ),
        );
      }
    }

    treeNode = TreeNode(
      content: Row(
        children: [
          const Icon(Icons.memory),
          const SizedBox(width: 2.0),
          Text(nodeName),
        ],
      ),
      children: children,
    );

    List<dynamic> subModules = node['subModules'];
    if (subModules.isNotEmpty) {
      for (var module in subModules) {
        treeNode.children!.add(buildTreeFromJson(module));
      }
    }

    return treeNode;
  }

  Widget genModuleTree() {
    return FutureBuilder<String>(
      future: futureModuleTree,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            Map jsonData = json.decode(snapshot.data!);
            List<TreeNode> nodes = [];
            var root = buildTreeFromJson(jsonData);
            nodes.add(root);
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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('ROHD DevTools Extension'),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: screenSize.width / 3,
                        height: screenSize.width / 2.6,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Icon(Icons.account_tree),
                                    SizedBox(
                                      width: 10,
                                    ),
                                    Text('Module Tree'),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.search),
                                            onPressed: () {},
                                          ),
                                          SizedBox(
                                            width: 10,
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.refresh),
                                            onPressed: () =>
                                                refreshModuleTree(),
                                          ),
                                        ],
                                      ),
                                    )
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

                      // Here is the container for Widget Tree Details, Waveform, Schematic
                      SizedBox(
                        width: screenSize.width / 3,
                        height: screenSize.width / 2.6,
                        child: const Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              DetailsNavBar(),
                              ButtonBar(
                                alignment: MainAxisAlignment.start,
                                children: [],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
