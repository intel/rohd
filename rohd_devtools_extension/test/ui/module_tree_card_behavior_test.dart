// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_card_behavior_test.dart
// Tests module-tree card behavior.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/tree_search_term_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';

void main() {
  testWidgets('labels and selects the module tree through cubits',
      (tester) async {
    final root = TreeModel(
      name: 'generated_top_instance',
      definition: 'TopDefinition',
      children: [
        TreeModel(name: 'child'),
      ],
    )..buildAddresses();
    final hierarchyCubit = DevToolsHierarchyCubit()..loadFromNode(root);
    final searchCubit = TreeSearchTermCubit();
    addTearDown(hierarchyCubit.close);
    addTearDown(searchCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: hierarchyCubit),
          BlocProvider.value(value: searchCubit),
        ],
        child: MaterialApp(
          home: Scaffold(body: ModuleTreeCard(futureModuleTree: root)),
        ),
      ),
    );

    expect(find.text('TopDefinition'), findsOneWidget);
    expect(find.text('generated_top_instance'), findsNothing);

    await tester.tap(find.text('TopDefinition'));
    await tester.pump();
    expect(hierarchyCubit.selectedModule, same(root));
  });
}
