// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bit_expansion_menu_test.dart
// Tests for bit expansion popup-menu items and action resolution.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  testWidgets('buildBitExpansionMenuItems creates divider and actions',
      (tester) async {
    final items = buildBitExpansionMenuItems(
      width: 16,
      includeDivider: true,
      fontSize: 11,
      itemHeight: 28,
    );

    expect(items, hasLength(3));
    expect(items[0], isA<PopupMenuDivider>());
    expect((items[1] as PopupMenuItem<String>).value, 'expand_bits');
    expect((items[2] as PopupMenuItem<String>).value, 'define_fields');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              (items[1] as PopupMenuItem<String>).child!,
              (items[2] as PopupMenuItem<String>).child!,
            ],
          ),
        ),
      ),
    );

    expect(find.text('Expand Bits [16]'), findsOneWidget);
    expect(find.text('Define Bit Fields [16]...'), findsOneWidget);
  });

  testWidgets('resolveBitExpansionMenuValue expands small widths immediately',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final action = await resolveBitExpansionMenuValue(
      context,
      value: BitExpansionMenuValues.expandBits,
      signalName: 'data',
      width: BitFieldUtils.expandThreshold,
    );

    expect(action, isA<BitExpandRangeAction>());
    final range = action! as BitExpandRangeAction;
    expect(range.bitStart, 0);
    expect(range.bitEnd, BitFieldUtils.expandThreshold - 1);
    expect(
      await resolveBitExpansionMenuValue(
        context,
        value: 'other',
        signalName: 'data',
        width: 4,
      ),
      isNull,
    );
  });

  testWidgets('resolveBitExpansionMenuValue uses dialogs for large ranges',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final rangeFuture = resolveBitExpansionMenuValue(
      context,
      value: BitExpansionMenuValues.expandBits,
      signalName: 'bus',
      width: BitFieldUtils.expandThreshold + 1,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6:3');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final range = await rangeFuture as BitExpandRangeAction;
    expect(range.bitStart, 3);
    expect(range.bitEnd, 6);

    final fieldsFuture = resolveBitExpansionMenuValue(
      context,
      value: BitExpansionMenuValues.defineFields,
      signalName: 'bus',
      width: 16,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'upper 15:8\nlower 7:0');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final fields = await fieldsFuture as BitDefineFieldsAction;
    expect(fields.fields.map((field) => field.name), ['upper', 'lower']);
  });
}
