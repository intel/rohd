import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/rohd_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_search_term_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/signal_details_card.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_card.dart';

class TreeStructurePage extends ConsumerWidget {
  const TreeStructurePage({
    super.key,
    required this.screenSize,
    required this.futureModuleTree,
    required this.selectedModule,
  });

  final Size screenSize;
  final AsyncValue<TreeModel> futureModuleTree;
  final TreeModel? selectedModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Module Tree render here (Left Section)
            SizedBox(
              width: screenSize.width / 2,
              height: screenSize.width / 2.6,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(Icons.account_tree),
                            const SizedBox(width: 10),
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
                      SizedBox(
                        height: screenSize.width / 2,
                        width: screenSize.width / 3,
                        // TODO: Why this child keep center?
                        child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: ModuleTreeCard(
                              futureModuleTree: futureModuleTree,
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(
              width: 20,
            ),

            // Signal Table Right Section Module
            SizedBox(
              width: screenSize.width / 3,
              height: screenSize.width / 2.6,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ModuleTreeDetailsNavbar(),
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 20),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SignalDetailsCard(
                            module: selectedModule,
                            signalService: ref.watch(signalServiceProvider),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
