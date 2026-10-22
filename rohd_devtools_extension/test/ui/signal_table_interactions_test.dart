// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat, SignalValueFormat, SignalValueFormatRegistry;

Future<void> _openContextMenu(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Widget _table({
  required TreeModel module,
  String? searchTerm,
  bool inputSelected = true,
  bool outputSelected = true,
  bool inoutSelected = true,
  bool internalsSelected = true,
  ({String value, bool computed})? Function(String signalPath)?
      signalValueFallback,
  void Function(List<String> signalPaths)? onSendSignals,
  void Function(RohdSourceFormat format, List<String> paths)? onGoToSource,
  List<RohdSourceFormat> Function()? availableSourceFormats,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SignalTable(
          selectedModule: module,
          searchTerm: searchTerm,
          inputSelectedVal: inputSelected,
          outputSelectedVal: outputSelected,
          inoutSelectedVal: inoutSelected,
          internalsSelectedVal: internalsSelected,
          signalValueFallback: signalValueFallback,
          onSendSignals: onSendSignals,
          onGoToSource: onGoToSource,
          availableSourceFormats: availableSourceFormats,
        ),
      ),
    );

void main() {
  testWidgets(
    'performs top-level copy, send, source, and format menu actions',
    (tester) async {
      final wide = SignalModel(
        name: 'wide',
        direction: 'output',
        value: "4'hf",
        width: 4,
      );
      final module = TreeModel(
        name: 'top',
        signals: [wide],
        children: const [],
      )..buildAddresses();
      final sent = <List<String>>[];
      final sourceRequests =
          <({RohdSourceFormat format, List<String> paths})>[];
      addTearDown(SignalValueFormatRegistry.clear);

      await tester.pumpWidget(
        _table(
          module: module,
          onSendSignals: sent.add,
          onGoToSource: (format, paths) {
            sourceRequests.add((format: format, paths: paths));
          },
          availableSourceFormats: () => const [RohdSourceFormat.rohd],
        ),
      );

      final signalName = find.text('wide');
      await _openContextMenu(tester, signalName);
      expect(find.text('Copy Full Path'), findsOneWidget);
      expect(find.text('Send Signal'), findsOneWidget);
      expect(find.text('Go to ROHD Source'), findsOneWidget);
      expect(find.text('Format As'), findsOneWidget);
      await tester.tap(find.text('Copy Full Path'));
      await tester.pump();
      expect(find.text('Copied: top/wide'), findsOneWidget);

      await _openContextMenu(tester, signalName);
      await tester.tap(find.text('Send Signal'));
      await tester.pumpAndSettle();
      expect(sent, [
        ['top/wide'],
      ]);

      await _openContextMenu(tester, signalName);
      await tester.tap(find.text('Go to ROHD Source'));
      await tester.pumpAndSettle();
      expect(sourceRequests, hasLength(1));
      expect(sourceRequests.single.format, RohdSourceFormat.rohd);
      expect(sourceRequests.single.paths, ['top/wide']);

      await _openContextMenu(tester, signalName);
      await tester.tap(find.text('Format As'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Binary'));
      await tester.pump();

      final address = wide.address;
      expect(address, isNotNull);
      expect(
        SignalValueFormatRegistry.formatFor(address!),
        SignalValueFormat.binary,
      );
    },
  );

  testWidgets('shift-expands and collapses all nested typed fields', (
    tester,
  ) async {
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
                {
                  'name': 'low',
                  'width': 4,
                  'bits': List<int>.generate(4, (index) => index),
                },
                {
                  'name': 'high',
                  'width': 4,
                  'bits': List<int>.generate(4, (index) => index + 4),
                },
              ],
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
    final module = TreeModel(
      name: 'typed',
      signals: [packet],
      children: const [],
    )..buildAddresses();

    await tester.pumpWidget(_table(module: module));
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
    final packetExpand = expandForText('packet');
    expect(packetExpand, findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(packetExpand);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: table, matching: find.text('payload')), findsOne);
    expect(find.descendant(of: table, matching: find.text('low')), findsOne);
    expect(find.descendant(of: table, matching: find.text('high')), findsOne);

    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: table, matching: find.text('low')), findsNothing);
    expect(
      find.descendant(of: table, matching: find.text('high')),
      findsNothing,
    );
  });

  testWidgets('filters regex and invalid expressions and evaluates fallbacks', (
    tester,
  ) async {
    final module = TreeModel(
      name: 'top',
      signals: [
        SignalModel(
          name: 'alpha',
          direction: 'input',
          value: "1'b0",
          width: 1,
        ),
        SignalModel(
          name: 'outbound',
          direction: 'output',
          value: '0xff',
          width: 8,
        ),
        SignalModel(
          name: 'computed',
          direction: 'output',
          width: 4,
        ),
        SignalModel(
          name: 'internalOnly',
          width: 1,
          value: "1'b1",
        ),
      ],
      children: const [],
    )..buildAddresses();
    final fallbackPaths = <String>[];

    await tester.pumpWidget(
      _table(
        module: module,
        searchTerm: 'OUT.*',
        internalsSelected: false,
      ),
    );
    expect(find.text('outbound'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);

    await tester.pumpWidget(
      _table(
        module: module,
        searchTerm: '[',
        internalsSelected: false,
      ),
    );
    expect(find.text('outbound'), findsNothing);

    await tester.pumpWidget(
      _table(
        module: module,
        searchTerm: 'internal',
        inputSelected: false,
        outputSelected: false,
        inoutSelected: false,
      ),
    );
    expect(find.text('internalOnly'), findsOneWidget);

    await tester.pumpWidget(
      _table(
        module: module,
        internalsSelected: false,
        signalValueFallback: (path) {
          fallbackPaths.add(path);
          return path == 'top/computed'
              ? (value: "4'ha", computed: true)
              : null;
        },
      ),
    );
    expect(fallbackPaths, contains('top/computed'));
    expect(find.text("4'ha"), findsOneWidget);
  });

  testWidgets('expands large nested fields and routes subfield source actions',
      (tester) async {
    final packet = SignalModel(
      name: 'packet',
      direction: 'input',
      value: "10'h3ff",
      width: 10,
      logicType: {
        'fields': [
          {
            'name': 'payload',
            'width': 10,
            'bits': List<int>.generate(10, (index) => index),
            'type': {
              'fields': List<Map<String, dynamic>>.generate(
                10,
                (index) => {
                  'name': 'field$index',
                  'width': 1,
                  'bits': [index],
                },
              ),
            },
          },
        ],
      },
    );
    final module = TreeModel(
      name: 'typed',
      signals: [packet],
      children: const [],
    )..buildAddresses();
    final sourceRequests = <({RohdSourceFormat format, List<String> paths})>[];

    await tester.pumpWidget(
      _table(
        module: module,
        onGoToSource: (format, paths) {
          sourceRequests.add((format: format, paths: paths));
        },
        availableSourceFormats: () => const [RohdSourceFormat.rohd],
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

    await tester.tap(expandForText('packet'));
    await tester.pumpAndSettle();
    await tester.tap(expandForText('payload'));
    await tester.pumpAndSettle();

    expect(find.text('Expand (10 fields)'), findsOneWidget);
    await tester.tap(find.text('Expand (10 fields)'));
    await tester.pumpAndSettle();

    final field = find.descendant(of: table, matching: find.text('field9'));
    expect(field, findsOneWidget);
    await tester.tap(field);
    await tester.pump();
    await _openContextMenu(tester, field);
    expect(find.text('Copy Value'), findsOneWidget);
    await tester.tap(find.text('Copy Value'));
    await tester.pumpAndSettle();

    await _openContextMenu(tester, field);
    await tester.tap(find.text('Go to ROHD Source'));
    await tester.pumpAndSettle();

    expect(sourceRequests, hasLength(1));
    expect(sourceRequests.single.format, RohdSourceFormat.rohd);
    expect(sourceRequests.single.paths, ['typed/packet_payload_field9']);
  });
}
