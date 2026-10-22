// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page_test.dart
// The tests for tree structure page functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

@TestOn('vm')
library;

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/devtools_dtd_connection.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat;
import 'package:rohd_schematic_viewer/schematic_viewer.dart'
    show EmbeddedSchematicViewer;

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

class _ControlledRohdServiceCubit extends RohdServiceCubit {
  _ControlledRohdServiceCubit() : super(manageServiceManager: false);

  int evalCalls = 0;

  void emitForTest(RohdServiceState state) => emit(state);

  @override
  Future<void> evalModuleTree() async {
    evalCalls++;
  }
}

class _ControlledSnapshotCubit extends SnapshotCubit {
  void emitForTest(SnapshotState state) => emit(state);
}

class _MockDtd extends Mock implements DartToolingDaemon {}

Future<void> _completeDtdCall(Invocation _) => Future<void>.value();

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

      when(() => rohdServiceCubit.state)
          .thenReturn(RohdServiceLoaded(treeModel));
      // Use Stream.empty() so the BlocListener never fires — avoids
      // _initWaveformDataSource() which needs the real serviceManager.
      // The BlocBuilder reads .state directly, so the UI still renders.
      when(() => rohdServiceCubit.stream)
          .thenAnswer((_) => const Stream.empty());
      when(() => treeSearchTermCubit.state).thenReturn(null);
      when(() => treeSearchTermCubit.stream)
          .thenAnswer((_) => const Stream.empty());

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

        when(() => rohdServiceCubit.state)
            .thenReturn(RohdServiceLoaded(treeModel));
        // Use Stream.empty() — same rationale as above.
        when(() => rohdServiceCubit.stream)
            .thenAnswer((_) => const Stream.empty());
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());

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

    testWidgets(
      'renders connection states and retries from the tree content',
      (tester) async {
        final serviceCubit = _ControlledRohdServiceCubit();
        addTearDown(serviceCubit.close);
        tester.view
          ..physicalSize = const Size(2000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: serviceCubit),
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
                body: TreeStructurePage(screenSize: Size(2000, 1000)),
              ),
            ),
          ),
        );
        await tester.pump();

        serviceCubit.emitForTest(RohdServiceLoading());
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsWidgets);

        serviceCubit.emitForTest(
          const RohdServiceError('target unavailable', StackTrace.empty),
        );
        await tester.pump();
        expect(find.text('Error: target unavailable'), findsOneWidget);

        serviceCubit.emitForTest(const RohdServiceLoaded(null));
        await tester.pump();
        expect(find.textContaining('Friendly Notice'), findsOneWidget);
        await tester.tap(find.text('Refresh'));

        serviceCubit.emitForTest(RohdServiceInitial());
        await tester.pump();
        expect(
          find.textContaining('Waiting for ROHD application'),
          findsOneWidget,
        );
        await tester.tap(find.text('Retry Connection'));

        expect(serviceCubit.evalCalls, 2);
      },
    );

    testWidgets(
      'synchronizes a loaded hierarchy and cleans up its DevTools services',
      (tester) async {
        final serviceCubit = _ControlledRohdServiceCubit();
        final treeService = MockTreeService();
        serviceCubit.treeService = treeService;
        addTearDown(serviceCubit.close);
        Future<Map<String, dynamic>?> nullMap(Invocation _) async => null;
        Future<String?> nullPath(Invocation _) async => null;
        when(treeService.getSchematicJson).thenReturn(null);
        when(() => treeService.fetchModuleFlc(any())).thenAnswer(nullMap);
        when(treeService.fetchFlcHierarchy).thenAnswer(nullMap);
        when(treeService.fetchFlcFilePath).thenAnswer(nullPath);
        tester.view
          ..physicalSize = const Size(2000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());
        final tree = TreeModelStub.simpleTreeModel;
        final connectionStates = <bool>[];
        void onConnectionStateChanged({required bool connected}) =>
            connectionStates.add(connected);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: serviceCubit),
              BlocProvider<TreeSearchTermCubit>.value(
                value: treeSearchTermCubit,
              ),
              BlocProvider<DetailsTabCubit>.value(value: detailsTabCubit),
              BlocProvider<DevToolsThemeCubit>.value(value: themeCubit),
              BlocProvider<DevToolsHierarchyCubit>.value(value: hierarchyCubit),
              BlocProvider<SnapshotCubit>.value(value: snapshotCubit),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: TreeStructurePage(
                  screenSize: const Size(2000, 1000),
                  onConnectionStateChanged: onConnectionStateChanged,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        serviceCubit.emitForTest(RohdServiceLoaded(tree));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(hierarchyCubit.currentRoot, same(tree));
        expect(hierarchyCubit.selectedModule, same(tree));
        expect(find.byType(ModuleTreeCard), findsOneWidget);

        final moduleTreeHeader = find
            .ancestor(
              of: find.text('Module Tree'),
              matching: find.byType(Row),
            )
            .first;
        await tester.tap(
          find.descendant(
              of: moduleTreeHeader, matching: find.byType(IconButton)),
        );
        expect(serviceCubit.evalCalls, 1);

        tester.state<TreeStructurePageState>(find.byType(TreeStructurePage))
          ..pauseVmConnection()
          ..pauseVmConnection()
          ..resumeVmConnection()
          ..resumeVmConnection();

        serviceCubit.emitForTest(RohdServiceInitial());
        await tester.pump();
        expect(connectionStates, contains(false));
      },
    );

    testWidgets(
      'forwards exact and leaf snapshot lookups to the embedded schematic host',
      (tester) async {
        final serviceCubit = _ControlledRohdServiceCubit();
        final controlledSnapshot = _ControlledSnapshotCubit();
        addTearDown(serviceCubit.close);
        addTearDown(controlledSnapshot.close);
        tester.view
          ..physicalSize = const Size(2000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());
        final tree = TreeModel(
          name: 'top',
          signals: [
            SignalModel(
              name: 'value',
              width: 4,
              direction: 'output',
            ),
          ],
          children: const [],
        );
        controlledSnapshot.emitForTest(
          const SnapshotLoaded(
            time: 10,
            signals: {
              'top/value': SignalSnapshot(
                signalId: 'top/value',
                name: 'value',
                value: "4'ha",
                width: 4,
                computed: true,
              ),
            },
          ),
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: serviceCubit),
              BlocProvider<TreeSearchTermCubit>.value(
                value: treeSearchTermCubit,
              ),
              BlocProvider<DetailsTabCubit>.value(value: detailsTabCubit),
              BlocProvider<DevToolsThemeCubit>.value(value: themeCubit),
              BlocProvider<DevToolsHierarchyCubit>.value(value: hierarchyCubit),
              BlocProvider<SnapshotCubit>.value(value: controlledSnapshot),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: TreeStructurePage(screenSize: Size(2000, 1000)),
              ),
            ),
          ),
        );
        await tester.pump();

        serviceCubit.emitForTest(RohdServiceLoaded(tree));
        await tester.pump();

        final viewer = tester.widget<EmbeddedSchematicViewer>(
          find.byType(EmbeddedSchematicViewer, skipOffstage: false),
        );
        final lookup = viewer.signalValueLookupFn;
        expect(lookup, isNotNull);
        expect(
          lookup!('top/value'),
          (value: "4'ha", computed: true, signalId: 'top/value'),
        );
        expect(
          lookup('other/value'),
          (value: "4'ha", computed: true, signalId: 'top/value'),
        );
        expect(lookup('other/missing'), isNull);
      },
    );

    testWidgets(
      'navigates a local FLC source from the schematic host callback',
      (tester) async {
        final connection =
            devToolsDtdConnection as ValueNotifier<DartToolingDaemon?>;
        final previousDtd = connection.value;
        connection.value = null;
        addTearDown(() => connection.value = previousDtd);
        final serviceCubit = _ControlledRohdServiceCubit();
        final treeService = MockTreeService();
        addTearDown(serviceCubit.close);
        Future<Map<String, dynamic>?> nullMap(Invocation _) async => null;
        Future<String?> nullPath(Invocation _) async => null;
        Future<String?> nullSourceLine(Invocation _) async => null;
        when(treeService.getSchematicJson).thenReturn(null);
        when(() => treeService.fetchModuleFlc('top')).thenAnswer(
          (_) async => {
            'version': 6,
            'files': ['lib/src/top.dart'],
            'modules': {
              'top': {
                'outputFiles': {
                  'sv': ['top.sv'],
                },
                'tree': [
                  ['0:10:5', 'signal@sv:20:3'],
                ],
              },
            },
          },
        );
        when(treeService.fetchFlcHierarchy).thenAnswer(nullMap);
        when(treeService.fetchFlcFilePath).thenAnswer(nullPath);
        when(() => treeService.fetchSourceLine(any(), any()))
            .thenAnswer(nullSourceLine);
        serviceCubit.treeService = treeService;
        tester.view
          ..physicalSize = const Size(2000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());
        final tree = TreeModel(
          name: 'top',
          signals: [
            SignalModel(name: 'signal', width: 1, direction: 'output'),
          ],
          children: const [],
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: serviceCubit),
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
                body: TreeStructurePage(screenSize: Size(2000, 1000)),
              ),
            ),
          ),
        );
        await tester.pump();
        serviceCubit.emitForTest(RohdServiceLoaded(tree));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        final viewer = tester.widget<EmbeddedSchematicViewer>(
          find.byType(EmbeddedSchematicViewer, skipOffstage: false),
        );
        final goToSource = viewer.onGoToSourceCallback;
        expect(goToSource, isNotNull);

        goToSource!(RohdSourceFormat.rohd, ['top/signal']);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.byType(PopupMenuItem<int>), findsNothing);
      },
    );

    testWidgets(
      'wires injected DTD shell and source navigation without network I/O',
      (tester) async {
        final connection =
            devToolsDtdConnection as ValueNotifier<DartToolingDaemon?>;
        final previousDtd = connection.value;
        addTearDown(() => connection.value = previousDtd);
        final dtd = _MockDtd();
        final serviceCubit = _ControlledRohdServiceCubit();
        final treeService = MockTreeService();
        addTearDown(serviceCubit.close);
        Future<Map<String, dynamic>?> nullMap(Invocation _) async => null;
        Future<String?> nullPath(Invocation _) async => null;
        when(() => dtd.isClosed).thenReturn(false);
        when(dtd.getRegisteredServices).thenAnswer(
          (_) async => const RegisteredServicesResponse(
            dtdServices: [],
            clientServices: [],
          ),
        );
        when(
          () => dtd.registerService(
            any(),
            any(),
            any(),
            capabilities: any(named: 'capabilities'),
          ),
        ).thenAnswer(_completeDtdCall);
        when(treeService.getSchematicJson).thenReturn(null);
        when(() => treeService.fetchModuleFlc(any())).thenAnswer(nullMap);
        when(treeService.fetchFlcHierarchy).thenAnswer(nullMap);
        when(treeService.fetchFlcFilePath).thenAnswer(nullPath);
        serviceCubit.treeService = treeService;
        tester.view
          ..physicalSize = const Size(2000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        when(() => treeSearchTermCubit.state).thenReturn(null);
        when(() => treeSearchTermCubit.stream)
            .thenAnswer((_) => const Stream.empty());
        connection.value = dtd;

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<RohdServiceCubit>.value(value: serviceCubit),
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
                body: TreeStructurePage(screenSize: Size(2000, 1000)),
              ),
            ),
          ),
        );
        await tester.pump();

        serviceCubit
            .emitForTest(RohdServiceLoaded(TreeModelStub.simpleTreeModel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        verify(
          () => dtd.registerService(
            'rohdDevtoolsShell',
            'execute',
            any(),
            capabilities: any(named: 'capabilities'),
          ),
        ).called(1);

        connection.value = null;
        await tester.pump();
        expect(find.byType(TreeStructurePage), findsOneWidget);
      },
    );
  });
}
