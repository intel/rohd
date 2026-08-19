// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// export_button_test.dart
// Tests for the PNG export toolbar button.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('renders camera icon, tooltip, and invokes callback',
      (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(
          body: Center(
            child: ExportPngButton(
              tooltip: 'Save waveform PNG',
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Save waveform PNG');

    await tester.tap(find.byType(ExportPngButton));
    await tester.pump();

    expect(taps, 1);
  });
}
