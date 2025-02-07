// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page_test.dart
// The tests for tree structure page functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

@TestOn('browser')
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';
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

    testWidgets('renders Module Tree and Signal Details sections',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TreeStructurePage(screenSize: const Size(800, 600)),
          ),
        ),
      );

      expect(find.text('Module Tree'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(ModuleTreeDetailsNavbar), findsOneWidget);
    });

    testWidgets('calls setTerm on TreeSearchTermCubit when text changes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: treeSearchTermCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'search term');
      verify(() => treeSearchTermCubit.setTerm('search term')).called(1);
    });

    testWidgets(
        'calls refreshModuleTree on RohdServiceCubit when refresh button is pressed',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: rohdServiceCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh));
      verify(() => rohdServiceCubit.refreshModuleTree()).called(1);
    });

    testWidgets(
        'displays CircularProgressIndicator when state is RohdServiceLoading',
        (tester) async {
      when(() => rohdServiceCubit.state).thenReturn(RohdServiceLoading());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: rohdServiceCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays error message when state is RohdServiceError',
        (tester) async {
      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceError('error message', StackTrace.current));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: rohdServiceCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      expect(find.text('Error: error message'), findsOneWidget);
    });

    testWidgets(
        'displays ModuleTreeCard when state is RohdServiceLoaded with treeModel',
        (tester) async {
      final treeModel = MockTreeModel();
      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: rohdServiceCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      expect(find.byType(ModuleTreeCard), findsOneWidget);
    });

    testWidgets(
        'displays SignalDetailsCard when state is RohdServiceLoaded with selected module',
        (tester) async {
      final treeModel = MockTreeModel();
      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: rohdServiceCubit,
              child: TreeStructurePage(screenSize: const Size(800, 600)),
            ),
          ),
        ),
      );

      expect(find.byType(SignalDetailsCard), findsOneWidget);
    });
  });
}
