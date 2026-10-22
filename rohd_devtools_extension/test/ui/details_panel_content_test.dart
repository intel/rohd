// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_panel_content.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required DevToolsHierarchyCubit hierarchyCubit,
    required DetailsTabCubit detailsTabCubit,
    required SnapshotCubit snapshotCubit,
    required DetailsPanelContent panel,
  }) =>
      tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: hierarchyCubit),
            BlocProvider.value(value: detailsTabCubit),
            BlocProvider.value(value: snapshotCubit),
          ],
          child: MaterialApp(home: Scaffold(body: panel)),
        ),
      );

  testWidgets('forwards tab visibility to configured panel hosts', (
    tester,
  ) async {
    final hierarchyCubit = DevToolsHierarchyCubit();
    final detailsTabCubit = DetailsTabCubit();
    final snapshotCubit = SnapshotCubit();
    addTearDown(hierarchyCubit.close);
    addTearDown(detailsTabCubit.close);
    addTearDown(snapshotCubit.close);
    final visibility = <bool>[];

    await pumpPanel(
      tester,
      hierarchyCubit: hierarchyCubit,
      detailsTabCubit: detailsTabCubit,
      snapshotCubit: snapshotCubit,
      panel: DetailsPanelContent(
        waveformConfig: const WaveformTabConfig(
          waveformViewer: Text('waveform host'),
        ),
        schematicConfig: SchematicTabConfig(
          assetPath: 'unused.json',
          customWidgetBuilder: ({required isVisible}) {
            visibility.add(isVisible);
            return Text('schematic visible: $isVisible');
          },
        ),
        customDetailsTab: const Text('details host'),
      ),
    );

    expect(find.text('details host'), findsOneWidget);
    expect(find.text('waveform host', skipOffstage: false), findsOneWidget);
    expect(
      find.text('schematic visible: false', skipOffstage: false),
      findsOneWidget,
    );
    expect(visibility.last, isFalse);

    detailsTabCubit.selectTab(DetailsTab.schematic);
    await tester.pump();

    expect(find.text('schematic visible: true'), findsOneWidget);
    expect(visibility.last, isTrue);
  });

  testWidgets('switches default details content when a module is selected', (
    tester,
  ) async {
    final module = TreeModel(
      name: 'counter',
      signals: [
        SignalModel(
          name: 'count',
          direction: 'output',
          value: "8'h00",
          width: 8,
        ),
      ],
      children: const [],
    );
    final root = TreeModel(name: 'top', signals: const [], children: [module])
      ..buildAddresses();
    final hierarchyCubit = DevToolsHierarchyCubit()..loadFromNode(root);
    final detailsTabCubit = DetailsTabCubit();
    final snapshotCubit = SnapshotCubit();
    addTearDown(hierarchyCubit.close);
    addTearDown(detailsTabCubit.close);
    addTearDown(snapshotCubit.close);

    await pumpPanel(
      tester,
      hierarchyCubit: hierarchyCubit,
      detailsTabCubit: detailsTabCubit,
      snapshotCubit: snapshotCubit,
      panel: DetailsPanelContent(
        waveformConfig: const WaveformTabConfig(
          waveformViewer: SizedBox.shrink(),
        ),
        schematicConfig: SchematicTabConfig(
          assetPath: 'unused.json',
          customWidgetBuilder: ({required isVisible}) => const SizedBox(),
        ),
        noModuleSelectedText: 'Choose a module',
      ),
    );

    expect(find.text('Choose a module'), findsOneWidget);
    expect(find.byType(SignalDetailsCard), findsNothing);

    hierarchyCubit.selectModule(module);
    await tester.pump();

    expect(find.text('Choose a module'), findsNothing);
    expect(find.byType(SignalDetailsCard), findsOneWidget);
  });
}
