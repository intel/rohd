// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// model_tree_card_test.dart
// The tests for model tree card functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';

import 'fixtures/tree_model.stub.dart';

void main() {
  testWidgets('ModuleTreeCard renders tree correctly', (tester) async {
    // Initialize the futureModuleTree
    final futureModuleTree = TreeModelStub.simpleTreeModel;

    // Wrap the ModuleTreeCard widget in MultiBlocProvider for Bloc Providers
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SelectedModuleCubit>(
              create: (_) => SelectedModuleCubit()),
          BlocProvider<TreeSearchTermCubit>(
              create: (_) => TreeSearchTermCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ModuleTreeCard(futureModuleTree: futureModuleTree),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    // Validate that the TreeView widget is present
    expect(find.text('counter'), findsOneWidget);
  });
}
