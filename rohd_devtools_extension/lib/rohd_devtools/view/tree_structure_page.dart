// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page.dart
// Page for the tree structure.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/rohd_service_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/tree_search_term_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/selected_module_cubit.dart';

class TreeStructurePage extends StatelessWidget {
  TreeStructurePage({
    super.key,
    required this.screenSize,
  });

  final Size screenSize;

  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  @override
  Widget build(BuildContext context) {
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
                                      context
                                          .read<TreeSearchTermCubit>()
                                          .setTerm(value);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: "Search Tree",
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () => context
                                      .read<RohdServiceCubit>()
                                      .evalModuleTree(),
                                ),
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
                                    child: BlocBuilder<RohdServiceCubit,
                                        RohdServiceState>(
                                      builder: (context, state) {
                                        if (state is RohdServiceLoading) {
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        } else if (state is RohdServiceLoaded) {
                                          final futureModuleTree =
                                              state.treeModel;
                                          if (futureModuleTree == null) {
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
                                              futureModuleTree:
                                                  futureModuleTree,
                                            );
                                          }
                                        } else if (state is RohdServiceError) {
                                          return Center(
                                            child:
                                                Text('Error: ${state.error}'),
                                          );
                                        } else {
                                          return const Center(
                                            child: Text('Unknown state'),
                                          );
                                        }
                                      },
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

            // Signal Table Right Section Module
            SizedBox(
              width: screenSize.width / 2,
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
                          child: BlocBuilder<SelectedModuleCubit,
                              SelectedModuleState>(
                            builder: (context, state) {
                              if (state is SelectedModuleLoaded) {
                                final selectedModule = state.module;
                                return SignalDetailsCard(
                                  module: selectedModule,
                                );
                              } else {
                                return const Center(
                                  child: Text('No module selected'),
                                );
                              }
                            },
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
