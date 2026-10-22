// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_panel_content.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtool_appbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_split_layout.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_search_overlay.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show AppBarOverlayTrigger;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

class _StaticSignalValueSource implements SignalValueSource {
  const _StaticSignalValueSource(this.data);

  final SignalSnapshotData data;

  @override
  Stream<SignalValueUpdateEvent>? get updates => null;

  @override
  Future<int?> getCurrentTime() async => null;

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) async => data;
}

class _OverlayStatus extends StatelessWidget {
  const _OverlayStatus();

  @override
  Widget build(BuildContext context) {
    final trigger = AppBarOverlayTrigger.of(context);
    if (trigger == null) {
      return const Text('overlay unavailable');
    }
    return ValueListenableBuilder<bool>(
      valueListenable: trigger,
      builder: (context, visible, _) => Text('overlay: $visible'),
    );
  }
}

HierarchyOccurrence _testHierarchy() => HierarchyOccurrence(
      name: 'top',
      definition: 'DemoTop',
      children: [
        HierarchyOccurrence(
          name: 'controller',
          signals: [
            SignalOccurrence(
              name: 'snapshot_value',
              direction: 'output',
              value: "8'h00",
              width: 8,
            ),
            SignalOccurrence(
              name: 'computed_value',
              direction: 'input',
              value: "1'h0",
              width: 1,
            ),
          ],
          children: [HierarchyOccurrence(name: 'leaf')],
        ),
        HierarchyOccurrence(name: 'primitive', isPrimitive: true),
        HierarchyOccurrence(name: 'struct_assign_hidden'),
      ],
    );

void main() {
  testWidgets(
    'drives split layout search, module selection, refresh, and resizers',
    (tester) async {
      final hierarchyCubit = DevToolsHierarchyCubit();
      final treeSearchCubit = TreeSearchTermCubit();
      final root = _testHierarchy();
      hierarchyCubit.loadFromNode(root);
      addTearDown(hierarchyCubit.close);
      addTearDown(treeSearchCubit.close);
      final verticalController = ScrollController();
      final horizontalController = ScrollController();
      addTearDown(verticalController.dispose);
      addTearDown(horizontalController.dispose);
      var refreshes = 0;

      tester.view
        ..physicalSize = const Size(1200, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: hierarchyCubit),
            BlocProvider.value(value: treeSearchCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DevToolsSplitLayout(
                moduleTreeConfig: ModuleTreePanelConfig(
                  icon: const Icon(Icons.account_tree),
                  refreshIcon: const Icon(Icons.refresh),
                  onRefresh: () => refreshes++,
                  treeContent: ModuleTreeCard(futureModuleTree: root),
                  bottomContent: Container(
                    key: const ValueKey('shell-content'),
                    color: Colors.blue,
                  ),
                  bottomContentHeight: 160,
                  verticalController: verticalController,
                  horizontalController: horizontalController,
                  hierarchyService: hierarchyCubit.currentService,
                ),
                detailsConfig: const DetailsPanelConfig(
                  content: Center(child: Text('Details canvas')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final searchField = find.byType(ModuleSearchField);
      final searchInput = find.descendant(
        of: searchField,
        matching: find.byType(TextField),
      );
      await tester.enterText(searchInput, 'controller');
      await tester.pump();
      final searchResult = find.ancestor(
        of: find.descendant(
          of: searchField,
          matching: find.text('controller'),
        ),
        matching: find.byType(InkWell),
      );
      expect(searchResult, findsOneWidget);
      await tester.tap(searchResult);
      await tester.pump();
      expect(hierarchyCubit.selectedModule?.name, 'controller');

      await tester.tap(find.byIcon(Icons.refresh));
      expect(refreshes, 1);

      final detailsDivider = find.byKey(
        const ValueKey('details-resize-divider'),
      );
      final initialDetailsDividerX = tester.getCenter(detailsDivider).dx;
      await tester.drag(detailsDivider, const Offset(180, 0));
      await tester.pump();
      expect(
        tester.getCenter(detailsDivider).dx,
        greaterThan(initialDetailsDividerX),
      );

      final shellContent = find.byKey(const ValueKey('shell-content'));
      final initialShellHeight = tester.getSize(shellContent).height;
      await tester.drag(
        find.byKey(const ValueKey('shell-resize-divider')),
        const Offset(0, -80),
      );
      await tester.pump();
      expect(
          tester.getSize(shellContent).height, greaterThan(initialShellHeight));
    },
  );

  testWidgets('shows details selection state and switches viewer tabs', (
    tester,
  ) async {
    final hierarchyCubit = DevToolsHierarchyCubit();
    final detailsTabCubit = DetailsTabCubit();
    final snapshotCubit = SnapshotCubit();
    final root = _testHierarchy();
    hierarchyCubit.loadFromNode(root);
    addTearDown(hierarchyCubit.close);
    addTearDown(detailsTabCubit.close);
    addTearDown(snapshotCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: hierarchyCubit),
          BlocProvider.value(value: detailsTabCubit),
          BlocProvider.value(value: snapshotCubit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DetailsPanelContent(
              noModuleSelectedText: 'Choose a test module',
              waveformConfig: const WaveformTabConfig(
                waveformViewer: Center(child: Text('Waveform canvas')),
              ),
              schematicConfig: SchematicTabConfig(
                assetPath: 'unused.json',
                customWidgetBuilder: ({required isVisible}) => Center(
                  child: Text(
                    isVisible ? 'Schematic canvas active' : 'Schematic hidden',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose a test module'), findsOneWidget);
    hierarchyCubit.selectModule(root.children.first);
    expect(hierarchyCubit.selectedModule, same(root.children.first));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SignalDetailsCard), findsOneWidget);

    final tabs = find.byType(ModuleTreeDetailsNavbar);
    await tester
        .tap(find.descendant(of: tabs, matching: find.text('Waveform')));
    await tester.pump();
    expect(detailsTabCubit.state, DetailsTab.waveform);
    expect(find.text('Waveform canvas'), findsOneWidget);

    await tester.tap(
      find.descendant(of: tabs, matching: find.text('Schematic')),
    );
    await tester.pump();
    expect(detailsTabCubit.state, DetailsTab.schematic);
    expect(find.text('Schematic canvas active'), findsOneWidget);
  });

  testWidgets(
    'propagates snapshots and panel overlay state through DevTools UI',
    (tester) async {
      final hierarchyCubit = DevToolsHierarchyCubit();
      final detailsTabCubit = DetailsTabCubit();
      final snapshotCubit = SnapshotCubit();
      final root = _testHierarchy();
      hierarchyCubit
        ..loadFromNode(root)
        ..selectModule(root.children.first);
      await snapshotCubit.takeSnapshot(
        const _StaticSignalValueSource({
          'top/controller/snapshot_value': {
            'name': 'snapshot_value',
            'value': "8'h2a",
            'width': 8,
            'direction': 'output',
          },
        }),
        42,
      );
      addTearDown(hierarchyCubit.close);
      addTearDown(detailsTabCubit.close);
      addTearDown(snapshotCubit.close);
      final fallbackPaths = <String>[];

      tester.view
        ..physicalSize = const Size(1000, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: hierarchyCubit),
            BlocProvider.value(value: detailsTabCubit),
            BlocProvider.value(value: snapshotCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DetailsPanelContent(
                waveformConfig: const WaveformTabConfig(
                  waveformViewer: _OverlayStatus(),
                ),
                schematicConfig: SchematicTabConfig(
                  assetPath: 'unused.json',
                  customWidgetBuilder: ({required isVisible}) =>
                      const SizedBox(),
                ),
                signalValueFallback: (path) {
                  fallbackPaths.add(path);
                  return (value: "1'h1", computed: true);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Snapshot @ 42'), findsOneWidget);
      expect(find.text("8'h2a"), findsOneWidget);
      expect(fallbackPaths, isNotEmpty);

      final navbar = find.byType(ModuleTreeDetailsNavbar);
      await tester.tap(
        find.descendant(of: navbar, matching: find.text('Waveform')),
      );
      await tester.pump();
      expect(detailsTabCubit.state, DetailsTab.waveform);
      expect(find.text('overlay: false'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(navbar));
      await tester.pump();
      expect(find.text('overlay: true'), findsOneWidget);

      await mouse.moveTo(const Offset(900, 700));
      await tester.pump();
      expect(find.text('overlay: false'), findsOneWidget);
    },
  );

  testWidgets('drives DevTools app bar tools, pause, and theme controls', (
    tester,
  ) async {
    final themeCubit = DevToolsThemeCubit();
    addTearDown(themeCubit.close);
    var pauseResumeCalls = 0;

    await tester.pumpWidget(
      BlocProvider.value(
        value: themeCubit,
        child: MaterialApp(
          home: Scaffold(
            appBar: DevtoolAppBar(
              hasColorEmoji: false,
              onPauseResume: () => pauseResumeCalls++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byTooltip('Pause waveform updates (keeps connection alive)'),
    );
    expect(pauseResumeCalls, 1);

    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Wave Viewer'), findsOneWidget);
    expect(find.text('Schematic Viewer'), findsOneWidget);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();

    expect(themeCubit.state, DevToolsThemeMode.dark);
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pump();
    expect(themeCubit.state, DevToolsThemeMode.light);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);

    await tester.pumpWidget(
      BlocProvider.value(
        value: themeCubit,
        child: MaterialApp(
          home: Scaffold(
            appBar: DevtoolAppBar(
              hasColorEmoji: false,
              isPaused: true,
              onPauseResume: () => pauseResumeCalls++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Resume waveform updates'));
    expect(pauseResumeCalls, 2);
  });
}
