// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// presentation_widgets_test.dart
// Tests for reusable DevTools presentation widgets.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/simulation_time_display.dart';

void main() {
  group('SimulationTimeDisplay', () {
    test('formats a time without a unit by default', () {
      expect(SimulationTimeDisplay.none.format(42), '42');
    });

    test('formats a time with a trimmed configured unit', () {
      expect(const SimulationTimeDisplay(unit: ' ns ').format(42), '42ns');
    });

    test('treats a blank configured unit as absent', () {
      expect(const SimulationTimeDisplay(unit: '   ').format(42), '42');
    });
  });

  group('PlatformIcon', () {
    testWidgets('renders emoji text when color emoji is available',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlatformIcon(
            Icons.waves,
            'wave',
            size: 24,
            color: Colors.teal,
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('wave'));
      expect(find.byType(Icon), findsNothing);
      expect(text.style!.fontSize, 24);
      expect(text.style!.color, Colors.teal);
    });

    testWidgets('renders the Material icon when emoji is unavailable',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlatformIcon(
            Icons.waves,
            'wave',
            size: 20,
            color: Colors.teal,
            hasColorEmoji: false,
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(find.text('wave'), findsNothing);
      expect(icon.icon, Icons.waves);
      expect(icon.size, 20);
      expect(icon.color, Colors.teal);
    });

    test('helper retains the requested rendering configuration', () {
      final icon = platformIcon(
        Icons.waves,
        'wave',
        size: 18,
        color: Colors.teal,
        hasColorEmoji: false,
      ) as PlatformIcon;

      expect(icon.nativeIcon, Icons.waves);
      expect(icon.emoji, 'wave');
      expect(icon.size, 18);
      expect(icon.color, Colors.teal);
      expect(icon.hasColorEmoji, isFalse);
    });
  });
}
