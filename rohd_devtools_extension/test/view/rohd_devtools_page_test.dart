// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_page_test.dart
// Tests for the top-level ROHD DevTools page composition.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

void main() {
  testWidgets('builds the extension module and toggles its theme',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: RohdDevToolsPage()));
    await tester.pump();

    expect(find.byType(RohdExtensionModule), findsOneWidget);
    expect(find.byType(DevtoolAppBar), findsOneWidget);
    expect(find.byType(TreeStructurePage), findsOneWidget);
    expect(find.text('ROHD DevTool (Beta)'), findsOneWidget);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pump();

    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
  });
}
