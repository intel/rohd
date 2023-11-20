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
  int counter = 0;

  String? message;

  late final EvalOnDartLibrary fooControllerEval;
  late final Disposable evalDisposable;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  @override
  void initState() {
    super.initState();
    _initEval();
    fooControllerEval = EvalOnDartLibrary(
      'package:rohd/src/diagnostics/inspector_service.dart',
      serviceManager.service!,
      serviceManager: serviceManager,
    );
    evalDisposable = Disposable();

    // extensionManager.registerEventHandler(
    //   DevToolsExtensionEventType.themeUpdate,
    //   (event) {
    //     final themeUpdateValue =
    //         event.data?[ExtensionEventParameters.theme] as String?;
    //     setState(() {
    //       message = themeUpdateValue;
    //     });
    //   },
    // );
  }

  @override
  void dispose() {
    fooControllerEval.dispose();
    evalDisposable.dispose();
    super.dispose();
  }

  Future<void> _initEval() async {
    await serviceManager.onServiceAvailable;
  }

  Future<String> evalModuleTree() async {
    final treeInstance = await fooControllerEval.evalInstance(
        'ModuleTree.instance.hierarchyJSON',
        isAlive: evalDisposable);

    final thingsListString =
        treeInstance.valueAsString ?? _defaultEvalResponseText;

    final thingsListJSON = json.decode(thingsListString);

    extensionManager.postMessageToDevTools(
      DevToolsExtensionEvent(
        DevToolsExtensionEventType.unknown,
        data: {'root': thingsListJSON['name']},
      ),
    );

    extensionManager.showBannerMessage(
      key: 'ROHD Hierarchy',
      type: 'warning',
      message: thingsListString,
      extensionName: 'rohd',
    );

    return thingsListString;
  }

  TreeNode buildTreeFromJson(dynamic node) {
    TreeNode treeNode;

    String nodeName = "Module: " + node['name'];

    // Create separate TreeNodes for inputs and outputs
    List<TreeNode> children = [];

    // Handle Inputs
    dynamic inputs = node['inputs'];
    String inputContentText = "Inputs: ";
    for (var key in inputs.keys) {
      inputContentText += "\n$key : ${inputs[key]['value']}";
    }
    children.add(TreeNode(content: Text(inputContentText)));

    // Handle Outputs
    dynamic outputs = node['outputs'];
    String outputContentText = "\nOutputs: ";
    for (var key in outputs.keys) {
      outputContentText += "\n$key : ${outputs[key]['value']}";
    }
    children.add(TreeNode(content: Text(outputContentText)));

    // Now create the root TreeNode with the given nodeName and children
    treeNode = TreeNode(content: Text(nodeName), children: children);

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
      future: evalModuleTree(),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        print(snapshot.data);
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            dynamic jsonData = json.decode(snapshot.data!);
            List<TreeNode> nodes = [];
            var root = buildTreeFromJson(jsonData);
            nodes.add(root);
            return SingleChildScrollView(
              child: TreeView(nodes: nodes),
            );
          }
        } else {
          return CircularProgressIndicator();
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
                Row(
                  children: [
                    // Here is the container of the Widget Tree
                    SizedBox(
                      width: screenSize.width / 3,
                      height: screenSize.width / 2.5,
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
                                        IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: () {},
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.refresh),
                                          onPressed: () {},
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),

                            // Module Tree render here
                            SingleChildScrollView(child: genModuleTree()),
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
                      height: screenSize.width / 2.5,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            BottomNavigationBar(
                              type: BottomNavigationBarType.fixed,
                              backgroundColor: const Color(0x1B1B1FEE),
                              selectedItemColor: Colors.white,
                              unselectedItemColor:
                                  Colors.white.withOpacity(.60),
                              selectedFontSize: 10,
                              unselectedFontSize: 10,
                              onTap: (value) {
                                // Respond to item press.
                              },
                              items: const [
                                BottomNavigationBarItem(
                                  label: 'Details',
                                  icon: Icon(Icons.info),
                                ),
                                BottomNavigationBarItem(
                                  label: 'Waveform',
                                  icon: Icon(Icons.cable),
                                ),
                                BottomNavigationBarItem(
                                  label: 'Schematic',
                                  icon: Icon(Icons.developer_board),
                                ),
                              ],
                            ),
                            const ButtonBar(
                              alignment: MainAxisAlignment.start,
                              children: [],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Padding(
                    //   padding: const EdgeInsets.all(8.0),
                    //   child: ElevatedButton(
                    //       onPressed: () => evalModuleTree(),
                    //       child: const Text('Refresh Hierarchy')),
                    // ),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
