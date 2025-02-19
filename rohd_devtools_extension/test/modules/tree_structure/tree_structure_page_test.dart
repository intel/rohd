// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page_test.dart
// The tests for tree structure page functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

@Skip('Currently failing, difficulty debugging due to flutter testing bug')
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  group('TreeStructurePage', () {
    late RohdServiceCubit rohdServiceCubit;
    late TreeSearchTermCubit treeSearchTermCubit;

    setUp(() {
      rohdServiceCubit = MockRohdServiceCubit();
      treeSearchTermCubit = MockTreeSearchTermCubit();
    });

    testWidgets(
        'displays ModuleTreeCard when state is RohdServiceLoaded with treeModel',
        (tester) async {
      final treeModel = MockTreeModel();

      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));
      when(() => rohdServiceCubit.stream)
          .thenAnswer((_) => Stream.value(RohdServiceLoaded(treeModel)));
      when(() => treeSearchTermCubit.state).thenReturn(null);
      when(() => treeSearchTermCubit.stream)
          .thenAnswer((_) => Stream.value(null));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RohdServiceCubit>.value(value: rohdServiceCubit),
            BlocProvider<TreeSearchTermCubit>.value(value: treeSearchTermCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TreeStructurePage(screenSize: const Size(2000, 1000)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ModuleTreeCard), findsOneWidget);
    });

    testWidgets(
        'displays SignalDetailsCard when state is RohdServiceLoaded with selected module',
        (tester) async {
      final treeModel = MockTreeModel();
      final signalModelList = <SignalModel>[
        MockSignalModel(),
        MockSignalModel()
      ];
      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));
      when(() => rohdServiceCubit.stream)
          .thenAnswer((_) => Stream.value(RohdServiceLoaded(treeModel)));
      when(() => treeModel.inputs).thenReturn(signalModelList);
      when(() => treeModel.outputs).thenReturn(signalModelList);
      when(() => treeSearchTermCubit.stream)
          .thenAnswer((_) => Stream.value(null));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RohdServiceCubit>.value(value: rohdServiceCubit),
            BlocProvider<TreeSearchTermCubit>.value(value: treeSearchTermCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(SignalDetailsCard), findsOneWidget);
    });
  });
}
