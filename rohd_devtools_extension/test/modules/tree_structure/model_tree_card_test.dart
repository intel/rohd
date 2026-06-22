// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// model_tree_card_test.dart
// The tests for model tree card functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>
@Skip('Currently failing, revisit to fix the failing testcase')
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  final mockSelectedModuleCubit = MockSelectedModuleCubit();
  final mockRohdServiceCubit = MockRohdServiceCubit();
  final mockTreeSearchTermCubit = MockTreeSearchTermCubit();

  setUpAll(() {
    // Register a fallback value for TreeModel
    registerFallbackValue(TreeModelStub.selectedModule);
  });

  testWidgets('ModuleTreeCard renders tree correctly',
      (WidgetTester tester) async {
    // Initialize the futureModuleTree
    final futureModuleTree = TreeModelStub.simpleTreeModel;

    // Mock the behavior of the cubits
    when(() => mockSelectedModuleCubit.state)
        .thenReturn(SelectedModuleInitial());
    when(() => mockRohdServiceCubit.state)
        .thenReturn(RohdServiceLoaded(futureModuleTree));
    when(() => mockTreeSearchTermCubit.state).thenReturn(null);
    when(() => mockTreeSearchTermCubit.stream)
        .thenAnswer((_) => Stream.value(null));

    // Wrap the ModuleTreeCard widget in MultiBlocProvider for Bloc Providers
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SelectedModuleCubit>.value(
              value: mockSelectedModuleCubit),
          BlocProvider<RohdServiceCubit>.value(value: mockRohdServiceCubit),
          BlocProvider<TreeSearchTermCubit>.value(
              value: mockTreeSearchTermCubit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ModuleTreeCard(futureModuleTree: futureModuleTree),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Validate that the TreeView widget is present
    expect(find.text('counter'), findsOneWidget);
  });
}
