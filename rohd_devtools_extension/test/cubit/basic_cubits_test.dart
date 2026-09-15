// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// basic_cubits_test.dart
// Tests for basic ROHD DevTools cubit state transitions.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/details_tab_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/selected_module_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/signal_search_term_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/theme_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/tree_search_term_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

void main() {
  group('search term cubits', () {
    test('store the latest signal and tree search terms', () async {
      final signalCubit = SignalSearchTermCubit();
      final treeCubit = TreeSearchTermCubit();
      addTearDown(signalCubit.close);
      addTearDown(treeCubit.close);

      expect(signalCubit.state, isNull);
      expect(treeCubit.state, isNull);

      signalCubit.setTerm('count');
      treeCubit.setTerm('counter/top');

      expect(signalCubit.state, 'count');
      expect(treeCubit.state, 'counter/top');
    });
  });

  test('DetailsTabCubit selects each available details view', () async {
    final cubit = DetailsTabCubit();
    addTearDown(cubit.close);

    expect(cubit.state, DetailsTab.details);

    cubit.selectTab(DetailsTab.waveform);
    expect(cubit.state, DetailsTab.waveform);

    cubit.selectTab(DetailsTab.schematic);
    expect(cubit.state, DetailsTab.schematic);
  });

  test('SelectedModuleCubit exposes the selected module', () async {
    final cubit = SelectedModuleCubit();
    addTearDown(cubit.close);
    final module = TreeModel(
      name: 'counter',
      inputs: const [],
      outputs: const [],
      subModules: const [],
    );

    expect(cubit.state, isA<SelectedModuleInitial>());

    cubit.setModule(module);

    expect(cubit.state, isA<SelectedModuleLoaded>());
    expect((cubit.state as SelectedModuleLoaded).module, same(module));
  });

  group('DevToolsThemeCubit', () {
    test('starts dark and toggles between the supported modes', () async {
      final cubit = DevToolsThemeCubit();
      addTearDown(cubit.close);

      expect(cubit.state, DevToolsThemeMode.dark);
      expect(cubit.isDark, isTrue);

      cubit.toggleTheme();
      expect(cubit.state, DevToolsThemeMode.light);
      expect(cubit.isDark, isFalse);

      cubit.toggleTheme();
      expect(cubit.state, DevToolsThemeMode.dark);
    });

    test('sets an explicit theme mode', () async {
      final cubit = DevToolsThemeCubit();
      addTearDown(cubit.close);

      cubit.setTheme(DevToolsThemeMode.light);

      expect(cubit.state, DevToolsThemeMode.light);
      expect(cubit.isDark, isFalse);
    });
  });
}
