// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// model_tree_card_test.dart
// The tests for model tree card functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  final mockHierarchyCubit = MockDevToolsHierarchyCubit();
  final mockRohdServiceCubit = MockRohdServiceCubit();
  final mockTreeSearchTermCubit = MockTreeSearchTermCubit();

  setUpAll(() {
    // Register a fallback value for TreeModel
    registerFallbackValue(TreeModelStub.selectedModule);
  });

  testWidgets('ModuleTreeCard renders tree correctly', (tester) async {
    // Initialize the futureModuleTree
    final futureModuleTree = TreeModelStub.simpleTreeModel;

    // Mock the behavior of the cubits
    when(() => mockHierarchyCubit.state).thenReturn(const HierarchyNotLoaded());
    when(
      () => mockHierarchyCubit.stream,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockRohdServiceCubit.state,
    ).thenReturn(RohdServiceLoaded(futureModuleTree));
    when(
      () => mockRohdServiceCubit.stream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockTreeSearchTermCubit.state).thenReturn(null);
    when(
      () => mockTreeSearchTermCubit.stream,
    ).thenAnswer((_) => const Stream.empty());

    // Wrap the ModuleTreeCard widget in MultiBlocProvider for Bloc Providers
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DevToolsHierarchyCubit>.value(value: mockHierarchyCubit),
          BlocProvider<RohdServiceCubit>.value(value: mockRohdServiceCubit),
          BlocProvider<TreeSearchTermCubit>.value(
            value: mockTreeSearchTermCubit,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ModuleTreeCard(futureModuleTree: futureModuleTree),
          ),
        ),
      ),
    );

    // Use pump() instead of pumpAndSettle() — the tree widget has
    // animations that may never fully settle in the test harness.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Validate that the TreeView widget is present
    expect(find.text('counter'), findsOneWidget);
  });

  testWidgets('ModuleTreeCard supports sibling occurrences with the same name',
      (tester) async {
    final tree = HierarchyOccurrence(
      name: 'top',
      children: [
        HierarchyOccurrence(name: 'repeated'),
        HierarchyOccurrence(name: 'repeated'),
      ],
    );
    when(() => mockHierarchyCubit.state).thenReturn(const HierarchyNotLoaded());
    when(
      () => mockHierarchyCubit.stream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockRohdServiceCubit.state).thenReturn(RohdServiceLoaded(tree));
    when(
      () => mockRohdServiceCubit.stream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockTreeSearchTermCubit.state).thenReturn(null);
    when(
      () => mockTreeSearchTermCubit.stream,
    ).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DevToolsHierarchyCubit>.value(value: mockHierarchyCubit),
          BlocProvider<RohdServiceCubit>.value(value: mockRohdServiceCubit),
          BlocProvider<TreeSearchTermCubit>.value(
            value: mockTreeSearchTermCubit,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: ModuleTreeCard(futureModuleTree: tree)),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
