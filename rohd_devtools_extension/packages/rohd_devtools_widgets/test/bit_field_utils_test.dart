// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bit_field_utils_test.dart
// Tests for shared bit-field parsing and formatting utilities.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  group('formatBitRange', () {
    test('formats single-bit and multi-bit ranges', () {
      expect(BitFieldUtils.formatBitRange(0, 1), '[0]');
      expect(BitFieldUtils.formatBitRange(4, 4), '[7:4]');
    });
  });

  group('parseBitRange', () {
    test('parses and clamps ranges and single bits', () {
      expect(BitFieldUtils.parseBitRange('7:4', 31), (7, 4));
      expect(BitFieldUtils.parseBitRange('4:7', 31), (7, 4));
      expect(BitFieldUtils.parseBitRange('99:30', 31), (31, 30));
      expect(BitFieldUtils.parseBitRange('5', 31), (5, 5));
      expect(BitFieldUtils.parseBitRange('99', 31), (31, 31));
    });

    test('rejects malformed ranges', () {
      expect(BitFieldUtils.parseBitRange('7:4:1', 31), isNull);
      expect(BitFieldUtils.parseBitRange('high:low', 31), isNull);
      expect(BitFieldUtils.parseBitRange('', 31), isNull);
    });
  });

  group('parseBitFieldDefs', () {
    test('parses named and unnamed bit fields', () {
      final fields = BitFieldUtils.parseBitFieldDefs(
        '''
exponent 31:21
mantissa   20:0
sign 31
7:4
0
ignored-name 3
''',
        31,
      );

      expect(fields, hasLength(5));
      expect(fields[0].name, 'exponent');
      expect(fields[0].high, 31);
      expect(fields[0].low, 21);
      expect(fields[1].name, 'mantissa');
      expect(fields[1].high, 20);
      expect(fields[1].low, 0);
      expect(fields[2].name, 'sign');
      expect(fields[2].high, 31);
      expect(fields[2].low, 31);
      expect(fields[3].name, '[7:4]');
      expect(fields[3].high, 7);
      expect(fields[3].low, 4);
      expect(fields[4].name, '[0]');
      expect(fields[4].high, 0);
      expect(fields[4].low, 0);
    });

    test('normalizes reversed and out-of-range indexes', () {
      final fields = BitFieldUtils.parseBitFieldDefs(
        '''
low_high 1:8
too_high 40:32
''',
        31,
      );

      expect(fields, hasLength(2));
      expect(fields[0].high, 8);
      expect(fields[0].low, 1);
      expect(fields[1].high, 31);
      expect(fields[1].low, 31);
    });
  });

  testWidgets('showBitRangeDialog returns parsed input and cancel returns null',
      (tester) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (context) {
            dialogContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showBitRangeDialog(
      dialogContext,
      signalName: 'data',
      width: 16,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2:5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(await future, (5, 2));

    final cancelled = showBitRangeDialog(
      dialogContext,
      signalName: 'data',
      width: 16,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await cancelled, isNull);
  });

  testWidgets('showDefineBitFieldsDialog parses edited definitions',
      (tester) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (context) {
            dialogContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showDefineBitFieldsDialog(
      dialogContext,
      signalName: 'floatBits',
      width: 32,
      existingDefs: const [
        BitFieldDef(name: 'sign', high: 31, low: 31),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('floatBits'), findsOneWidget);
    expect(find.textContaining('sign 31'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'sign 31\nexponent 30:23\nmantissa 22:0',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final fields = await future;
    expect(fields, hasLength(3));
    expect(fields![0].name, 'sign');
    expect(fields[1].name, 'exponent');
    expect(fields[1].high, 30);
    expect(fields[1].low, 23);
    expect(fields[2].name, 'mantissa');
  });
}
