// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_view.dart
// Main view for the app.
//
// 2025 January 28

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';

/// A [StatelessWidget] which reacts to the provided
/// [RohdDevToolsCubit] state and notifies it in response to user input.
class RohdDevToolsView extends StatefulWidget {
  const RohdDevToolsView({
    super.key,
    required this.screenSize,
    // required this.topModuleTree,
    // required this.selectedModule,
  });

  final Size screenSize;

  @override
  _RohdDevToolsViewState createState() =>
      _RohdDevToolsViewState(screenSize: screenSize);
}

class _RohdDevToolsViewState extends State<RohdDevToolsView> {
  final Size screenSize;
  // final TreeModel? topModuleTree;
  // final TreeModel? selectedModule;
  _RohdDevToolsViewState({
    required this.screenSize,
    // required this.topModuleTree,
    // required this.selectedModule,
  });

  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RohdDevToolsCubit, TreeModel?>(
        builder: (context, topModuleTree) {
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        // Module Tree Menu Bar
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
                                        // ref
                                        //     .read(treeSearchTermProvider.notifier)
                                        //     .setTerm(value);
                                      },
                                      decoration: const InputDecoration(
                                        labelText: "Search Tree",
                                      ),
                                    ),
                                  ),
                                  // IconButton(
                                  //   icon: const Icon(Icons.refresh),
                                  //   onPressed: () => ref
                                  //       .read(rohdModuleTreeProvider.notifier)
                                  //       .refreshModuleTree(),
                                  // ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // expand the available column
                      Expanded(
                        child: Scrollbar(
                          thumbVisibility: true,
                          controller: _vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            controller: _vertical,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    controller: _horizontal,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      controller: _horizontal,
                                      child: Builder(builder: (context) {
                                      // if (futureModuleTree) {
                                      //   return const Text(
                                      //     'please build your model!',
                                      //   );
                                      // } else {
                                      //   return ModuleTreeCard(
                                      //     futureModuleTree: futureModuleTree,
                                      //   );
                                      // }

                                      return 
                                          if (data == null) {
                                            return Expanded(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: const Text(
                                                  'Friendly Notice: Please make '
                                                  'sure that you use build() method '
                                                  'to build your module and put '
                                                  'the breakpoint at the '
                                                  'simulation time.',
                                                  style:
                                                      TextStyle(fontSize: 20),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            );
                                          } else {
                                            return ModuleTreeCard(
                                              futureModuleTree: data,
                                            );
                                          }
                                        },

                                       
                                      );
                                      ),
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
              ),

              const SizedBox(
                width: 20,
              ),

              // Signal Table Right Section Module
              SizedBox(
                width: screenSize.width / 2,
                height: screenSize.width / 2.6,
                // child: Card(
                //   clipBehavior: Clip.antiAlias,
                //   child: SingleChildScrollView(
                //     child: Column(
                //       crossAxisAlignment: CrossAxisAlignment.start,
                //       children: [
                //         // const ModuleTreeDetailsNavbar(),
                //         Padding(
                //           padding: const EdgeInsets.only(left: 20, right: 20),
                //           child: SingleChildScrollView(
                //             scrollDirection: Axis.vertical,
                //             child: SignalDetailsCard(
                //               module: selectedModule,
                //               signalService: ref.watch(signalServiceProvider),
                //             ),
                //           ),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
