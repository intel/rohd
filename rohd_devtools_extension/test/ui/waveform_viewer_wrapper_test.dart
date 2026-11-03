// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_viewer_wrapper_test.dart
// Tests the waveform viewer wrapper.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/waveform_viewer_wrapper.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart'
    show EmbeddedWaveViewer, WaveViewerThemeMode;

class _SnapshotSource implements SignalValueSource {
  const _SnapshotSource(this.data);

  final SignalSnapshotData data;

  @override
  Stream<SignalValueUpdateEvent>? get updates => null;

  @override
  Future<int?> getCurrentTime() async => null;

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) async => data;
}

Future<void> _pumpWrapper(
  WidgetTester tester, {
  required DevToolsThemeCubit themeCubit,
  required SnapshotCubit snapshotCubit,
  required DevToolsHierarchyCubit hierarchyCubit,
  required bool useSharedHierarchy,
}) =>
    tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: themeCubit),
          BlocProvider.value(value: snapshotCubit),
          BlocProvider.value(value: hierarchyCubit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: WaveformViewerWrapper(
                useSharedHierarchy: useSharedHierarchy,
                initialMonitoredSignalPaths: const ['top/child/value'],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'forwards shared DevTools state into the embedded waveform viewer',
    (tester) async {
      final themeCubit = DevToolsThemeCubit();
      final snapshotCubit = SnapshotCubit();
      final hierarchyCubit = DevToolsHierarchyCubit();
      final root = HierarchyOccurrence(
        name: 'top',
        children: [
          HierarchyOccurrence(
            name: 'child',
            signals: [
              SignalOccurrence(name: 'value', width: 1, direction: 'output'),
            ],
          ),
        ],
      );
      hierarchyCubit
        ..loadFromNode(root)
        ..selectModule(root.children.single);
      await snapshotCubit.takeSnapshot(
        const _SnapshotSource({
          'top/child/value': {
            'name': 'value',
            'value': "1'h1",
            'width': 1,
          },
        }),
        25,
      );
      addTearDown(themeCubit.close);
      addTearDown(snapshotCubit.close);
      addTearDown(hierarchyCubit.close);

      await _pumpWrapper(
        tester,
        themeCubit: themeCubit,
        snapshotCubit: snapshotCubit,
        hierarchyCubit: hierarchyCubit,
        useSharedHierarchy: true,
      );
      await tester.pump();

      var embedded = tester.widget<EmbeddedWaveViewer>(
        find.byType(EmbeddedWaveViewer),
      );
      expect(embedded.waveformApi, isNull);
      expect(embedded.externalHierarchy, same(hierarchyCubit.currentService));
      expect(embedded.selectedModule, same(root.children.single));
      expect(embedded.themeMode, WaveViewerThemeMode.dark);
      expect(embedded.lastSnapshotTimePs, 25);
      expect(embedded.isExtensionMode, isTrue);
      expect(embedded.initialMonitoredSignalPaths, ['top/child/value']);
      expect(embedded.onSnapshotRequested, isNotNull);
      expect(embedded.onVideoModeToggled, isNull);

      themeCubit.setTheme(DevToolsThemeMode.light);
      await snapshotCubit.takeSnapshot(
        const _SnapshotSource({
          'top/child/value': {
            'name': 'value',
            'value': "1'h0",
            'width': 1,
          },
        }),
        30,
      );
      await tester.pump();

      embedded = tester.widget<EmbeddedWaveViewer>(
        find.byType(EmbeddedWaveViewer),
      );
      expect(embedded.themeMode, WaveViewerThemeMode.light);
      expect(embedded.lastSnapshotTimePs, 30);

      await _pumpWrapper(
        tester,
        themeCubit: themeCubit,
        snapshotCubit: snapshotCubit,
        hierarchyCubit: hierarchyCubit,
        useSharedHierarchy: false,
      );
      await tester.pump();

      embedded = tester.widget<EmbeddedWaveViewer>(
        find.byType(EmbeddedWaveViewer),
      );
      expect(embedded.externalHierarchy, isNull);
      expect(embedded.selectedModule, isNull);
    },
  );
}
