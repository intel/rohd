// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// export_toast_test.dart
// Tests for export toast overlay behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('showExportToast inserts and removes an overlay entry',
      (tester) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            toastContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    showExportToast(
      toastContext,
      'Saved: waveform.png',
      duration: const Duration(milliseconds: 10),
    );
    await tester.pump();

    expect(find.text('Saved: waveform.png'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(find.text('Saved: waveform.png'), findsNothing);
  });
}
