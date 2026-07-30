// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page_test.dart
// The tests for tree structure page functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  group('TreeStructurePage', () {
    late RohdServiceCubit rohdServiceCubit;

    setUp(() {
      rohdServiceCubit = MockRohdServiceCubit();
    });

    Future<void> pumpTreeStructurePage(
      WidgetTester tester, {
      required TreeModel treeModel,
      TreeModel? selectedModule,
      Size screenSize = const Size(2000, 1000),
    }) async {
      final selectedModuleCubit = SelectedModuleCubit();
      if (selectedModule != null) {
        selectedModuleCubit.setModule(selectedModule);
      }

      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));
      when(() => rohdServiceCubit.stream)
          .thenAnswer((_) => Stream.value(RohdServiceLoaded(treeModel)));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RohdServiceCubit>.value(value: rohdServiceCubit),
            BlocProvider<TreeSearchTermCubit>(
                create: (_) => TreeSearchTermCubit()),
            BlocProvider<SelectedModuleCubit>(
                create: (_) => selectedModuleCubit),
            BlocProvider<DetailsTabCubit>(create: (_) => DetailsTabCubit()),
            BlocProvider<SnapshotCubit>(create: (_) => SnapshotCubit()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TreeStructurePage(screenSize: screenSize),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'displays ModuleTreeCard when state is RohdServiceLoaded '
      'with treeModel',
      (tester) async {
        await pumpTreeStructurePage(
          tester,
          treeModel: TreeModelStub.simpleTreeModel,
        );

        expect(find.byType(ModuleTreeCard), findsOneWidget);
      },
    );

    testWidgets(
      'displays SignalDetailsCard when state is RohdServiceLoaded '
      'with selected module',
      (tester) async {
        await pumpTreeStructurePage(
          tester,
          treeModel: TreeModelStub.simpleTreeModel,
          selectedModule: TreeModelStub.selectedModule,
        );

        expect(find.byType(SignalDetailsCard), findsOneWidget);
      },
    );
  });
}
