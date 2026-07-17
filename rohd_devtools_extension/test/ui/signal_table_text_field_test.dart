// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table_text_field_test.dart
// Tests for signal table filter text field behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table_text_field.dart';

void main() {
  testWidgets('forwards typed filters and clears them on request',
      (tester) async {
    final terms = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SignalTableTextField(
                labelText: 'Signals',
                onChanged: terms.add,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Signals (regex supported)'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsNothing);

    await tester.enterText(find.byType(TextField), 'counter.*');
    await tester.pump();

    expect(terms, ['counter.*']);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(terms.last, '');
  });
}
