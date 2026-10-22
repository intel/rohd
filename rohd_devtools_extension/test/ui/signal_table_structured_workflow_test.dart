// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';

void main() {
  testWidgets(
    'expands typed signals and sends real derived field paths',
    (tester) async {
      final packet = SignalModel(
        name: 'packet',
        direction: 'input',
        value: "9'h101",
        width: 9,
        logicType: {
          'typeName': 'Packet',
          'fields': [
            {
              'name': 'payload',
              'width': 8,
              'bits': List<int>.generate(8, (index) => index),
              'type': {
                'fields': [
                  'low',
                  'high',
                ]
                    .asMap()
                    .entries
                    .map(
                      (entry) => {
                        'name': entry.value,
                        'width': 4,
                        'bits': List<int>.generate(
                          4,
                          (index) => entry.key * 4 + index,
                        ),
                      },
                    )
                    .toList(),
              },
            },
            {
              'name': 'valid',
              'width': 1,
              'bits': [8],
            },
          ],
        },
      );
      final lanes = SignalModel(
        name: 'lanes',
        direction: 'output',
        value: "40'h0123456789",
        width: 40,
        logicType: {
          'arrayDims': [10],
          'elementWidth': 4,
        },
      );
      final module = TreeModel(
        name: 'typed',
        signals: [packet, lanes],
        children: const [],
      )..buildAddresses();
      final sentSignalBatches = <List<String>>[];

      tester.view
        ..physicalSize = const Size(1000, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalTable(
              selectedModule: module,
              searchTerm: null,
              inputSelectedVal: true,
              outputSelectedVal: true,
              inoutSelectedVal: true,
              onSendSignals: sentSignalBatches.add,
            ),
          ),
        ),
      );

      final table = find.byType(SignalTable);

      Finder expandForText(String text) => find.descendant(
            of: find
                .ancestor(
                  of: find.descendant(of: table, matching: find.text(text)),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byIcon(Icons.chevron_right),
          );

      Future<void> openContextMenu(Finder finder) async {
        await tester.ensureVisible(finder);
        final gesture = await tester.startGesture(
          tester.getCenter(finder),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
        await gesture.up();
        await tester.pump();
        await tester.pumpAndSettle();
      }

      final packetExpand = expandForText('packet');
      expect(packetExpand, findsOneWidget);
      await tester.tap(packetExpand);
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: table, matching: find.text('payload')), findsOne);
      expect(
          find.descendant(of: table, matching: find.text('valid')), findsOne);

      final payloadExpand = expandForText('payload');
      expect(payloadExpand, findsOneWidget);
      await tester.tap(payloadExpand);
      await tester.pumpAndSettle();
      final lowField = find.descendant(of: table, matching: find.text('low'));
      expect(lowField, findsOneWidget);
      await openContextMenu(lowField);
      expect(find.text('Send Field'), findsOneWidget);
      await tester.tap(find.text('Send Field'));
      await tester.pumpAndSettle();

      final lanesExpand = expandForText('lanes');
      expect(lanesExpand, findsOneWidget);
      await tester.tap(lanesExpand);
      await tester.pumpAndSettle();
      expect(find.text('Select Range (0:9)...'), findsOneWidget);
      await tester.tap(find.text('Select Range (0:9)...'));
      await tester.pumpAndSettle();
      final rangeDialog = find.byType(AlertDialog);
      expect(rangeDialog, findsOneWidget);
      final rangeInput = find.descendant(
        of: rangeDialog,
        matching: find.byType(TextField),
      );
      await tester.enterText(rangeInput, '0:1');
      await tester.tap(
        find.descendant(of: rangeDialog, matching: find.text('OK')),
      );
      await tester.pumpAndSettle();

      final firstLane = find.descendant(of: table, matching: find.text('[0]'));
      expect(firstLane, findsOneWidget);
      await openContextMenu(firstLane);
      expect(find.text('Send Field'), findsOneWidget);
      await tester.tap(find.text('Send Field'));
      await tester.pumpAndSettle();

      expect(
        sentSignalBatches,
        [
          ['typed/packet_payload_low'],
          ['typed/lanes_0_'],
        ],
      );
    },
  );
}
