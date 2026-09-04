// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page_test.dart
// The tests for tree structure page functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  group('TreeStructurePage', () {
    late MockRohdServiceCubit rohdServiceCubit;
    late MockTreeSearchTermCubit treeSearchTermCubit;
    late DetailsTabCubit detailsTabCubit;
    late DevToolsThemeCubit themeCubit;
    late DevToolsHierarchyCubit hierarchyCubit;
    late SnapshotCubit snapshotCubit;

    setUp(() {
      rohdServiceCubit = MockRohdServiceCubit();
      treeSearchTermCubit = MockTreeSearchTermCubit();
      detailsTabCubit = DetailsTabCubit();
      themeCubit = DevToolsThemeCubit();
      hierarchyCubit = DevToolsHierarchyCubit();
      snapshotCubit = SnapshotCubit();
    });

    tearDown(() {
      unawaited(detailsTabCubit.close());
      unawaited(themeCubit.close());
      unawaited(hierarchyCubit.close());
      unawaited(snapshotCubit.close());
    });

    testWidgets(
        'displays ModuleTreeCard when state is RohdServiceLoaded with '
        'treeModel', (tester) async {
      // Provide enough room for the split layout to render without overflow.
      tester.view.physicalSize = const Size(2000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final treeModel = TreeModelStub.simpleTreeModel;

      when(
        () => rohdServiceCubit.state,
      ).thenReturn(RohdServiceLoaded(treeModel));
      // Use Stream.empty() so the BlocListener never fires — avoids
      // _initWaveformDataSource() which needs the real serviceManager.
      // The BlocBuilder reads .state directly, so the UI still renders.
      when(
        () => rohdServiceCubit.stream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => treeSearchTermCubit.state).thenReturn(null);
      when(
        () => treeSearchTermCubit.stream,
      ).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RohdServiceCubit>.value(value: rohdServiceCubit),
            BlocProvider<TreeSearchTermCubit>.value(value: treeSearchTermCubit),
            BlocProvider<DetailsTabCubit>.value(value: detailsTabCubit),
            BlocProvider<DevToolsThemeCubit>.value(value: themeCubit),
            BlocProvider<DevToolsHierarchyCubit>.value(value: hierarchyCubit),
            BlocProvider<SnapshotCubit>.value(value: snapshotCubit),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TreeStructurePage(screenSize: Size(2000, 1000)),
            ),
          ),
        ),
      );

      // Use pump() instead of pumpAndSettle() because the complex widget
      // tree (SplitPane, WaveformViewer, Schematic) has persistent animations.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ModuleTreeCard), findsOneWidget);
    });

    testWidgets(
      'displays SignalDetailsCard when state is RohdServiceLoaded with '
      'selected module',
      (tester) async {
        tester.view.physicalSize = const Size(2000, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final treeModel = TreeModelStub.simpleTreeModel;

        when(
          () => rohdServiceCubit.state,
        ).thenReturn(RohdServiceLoaded(treeModel));
        // Use Stream.empty() — same rationale as above.
        when(
          () => rohdServiceCubit.stream,
        ).thenAnswer((_) => const Stream.empty());
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(
          () => treeSearchTermCubit.stream,
        ).thenAnswer((_) => const Stream.empty());

        // Set hierarchy state to loaded with selected module
        hierarchyCubit
          ..loadFromNode(treeModel)
          ..selectModule(treeModel);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: rohdServiceCubit),
              BlocProvider<TreeSearchTermCubit>.value(
                value: treeSearchTermCubit,
              ),
              BlocProvider<DetailsTabCubit>.value(value: detailsTabCubit),
              BlocProvider<DevToolsThemeCubit>.value(value: themeCubit),
              BlocProvider<DevToolsHierarchyCubit>.value(value: hierarchyCubit),
              BlocProvider<SnapshotCubit>.value(value: snapshotCubit),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: TreeStructurePage(screenSize: Size(800, 600)),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(SignalDetailsCard), findsOneWidget);
      },
    );
  });
}
