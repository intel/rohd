// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtool_appbar_test.dart
// Tests for ROHD DevTools app bar and help controls.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/theme_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtool_appbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_help_button.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('renders persistent app bar controls and toggles the theme cubit',
      (tester) async {
    final cubit = DevToolsThemeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(
          home: Scaffold(appBar: DevtoolAppBar(hasColorEmoji: false)),
        ),
      ),
    );

    expect(find.text('ROHD DevTool (Beta)'), findsOneWidget);
    expect(find.text('Licenses'), findsOneWidget);
    expect(find.byType(DevToolsHelpButton), findsOneWidget);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    expect(const DevtoolAppBar().preferredSize.height, kToolbarHeight);

    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pump();

    expect(cubit.state, DevToolsThemeMode.light);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
  });

  testWidgets('passes DevTools help configuration to the markdown help control',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DevToolsHelpButton(isDark: true)),
    );

    final button = tester.widget<MarkdownHelpButton>(
      find.byType(MarkdownHelpButton),
    );
    expect(button.assetPath, 'assets/help/devtools_help.md');
    expect(button.isDark, isTrue);
  });
}
