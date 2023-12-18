import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_search_term_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/tree_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/detail_card_widget.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_widget.dart';
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
  String? message, inputSearchTerm, outputSearchTerm;

  late final EvalOnDartLibrary rohdControllerEval;
  late final Disposable evalDisposable;

  // services
  late final TreeService treeService;
  late final SignalService signalService;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  late Future<TreeModel> futureModuleTree;

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
    setState(() {
      // Use treeService to refresh the module tree.
      futureModuleTree = treeService.refreshModuleTree();
    });
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
                                    ref
                                        .read(treeSearchTermProvider.notifier)
                                        .setTerm(value);
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
                          child: ModuleTreeWidget(
                            futureModuleTree: futureModuleTree,
                          )),
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
                        child: DetailCard(
                          module: selectedModule,
                          signalService: signalService,
                        ),
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
}
