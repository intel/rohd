// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_details_card_test.dart
// Tests for signal-details card workflows.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';

final _module = TreeModel(
  name: 'top',
  signals: [
    SignalModel(name: 'input_enable', direction: 'input', value: '0', width: 1),
    SignalModel(
      name: 'output_value',
      direction: 'output',
      value: '00',
      width: 8,
    ),
    SignalModel(name: 'shared_bus', direction: 'inout', value: 'zz', width: 8),
  ],
  children: const [],
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    TreeModel? module,
    bool includeModule = true,
    SnapshotLoaded? snapshot,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: SignalDetailsCard(
                module: includeModule ? module ?? _module : null,
                snapshot: snapshot,
              ),
            ),
          ),
        ),
      );

  testWidgets('shows an empty state until a module is selected', (
    tester,
  ) async {
    await pumpCard(tester, includeModule: false);

    expect(find.text('No module selected'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('filters signals by search text and restores them when cleared', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.text('input_enable'), findsOneWidget);
    expect(find.text('output_value'), findsOneWidget);
    expect(find.text('shared_bus'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'output');
    await tester.pump();

    expect(find.text('input_enable'), findsNothing);
    expect(find.text('output_value'), findsOneWidget);
    expect(find.text('shared_bus'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('input_enable'), findsOneWidget);
    expect(find.text('output_value'), findsOneWidget);
    expect(find.text('shared_bus'), findsOneWidget);
  });

  testWidgets('hides directions selected in the filter dialog', (tester) async {
    await pumpCard(tester);

    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.filter_list),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();

    expect(find.text('input_enable'), findsNothing);
    expect(find.text('output_value'), findsOneWidget);
    expect(find.text('shared_bus'), findsNothing);
  });

  testWidgets('uses snapshot values and formats the snapshot time', (
    tester,
  ) async {
    await pumpCard(
      tester,
      snapshot: const SnapshotLoaded(
        time: 42,
        signals: {
          'output_value': SignalSnapshot(
            signalId: 'output_value',
            name: 'output_value',
            value: "8'hff",
            width: 8,
          ),
        },
      ),
    );

    expect(find.text('Value (@ 42)'), findsOneWidget);
    expect(find.text("8'hff"), findsOneWidget);
    expect(find.text("1'h0"), findsOneWidget);
  });
}
