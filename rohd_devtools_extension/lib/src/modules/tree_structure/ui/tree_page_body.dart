import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/rohd_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_search_term_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/detail_card_widget.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_widget.dart';

class TreePageBody extends StatelessWidget {
  const TreePageBody({
    super.key,
    required this.screenSize,
    required this.ref,
    required this.futureModuleTree,
    required this.selectedModule,
  });

  final Size screenSize;
  final WidgetRef ref;
  final AsyncValue<TreeModel> futureModuleTree;
  final TreeModel? selectedModule;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                              onPressed: () => ref
                                  .read(rohdModuleTreeProvider.notifier)
                                  .refreshModuleTree(),
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
                        signalService: ref.watch(signalServiceProvider),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
