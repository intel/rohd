// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_icon_test.dart
// Tests the schematic icon.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/schematic_icon.dart';

void main() {
  testWidgets(
    'paints at the requested size and updates for an explicit brightness',
    (tester) async {
      const iconKey = ValueKey('schematic-icon');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Center(
            child: SchematicIcon(key: iconKey, size: 28),
          ),
        ),
      );

      expect(
        tester.getSize(
          find.descendant(
            of: find.byKey(iconKey),
            matching: find.byType(CustomPaint),
          ),
        ),
        const Size.square(28),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Center(
            child: SchematicIcon(
              key: iconKey,
              size: 28,
              brightness: Brightness.light,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(
          find.descendant(
            of: find.byKey(iconKey),
            matching: find.byType(CustomPaint),
          ),
        ),
        const Size.square(28),
      );
    },
  );
}
