// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// markdown_help_button_test.dart
// Tests for markdown-backed help button loading and dialog rendering.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  const assetPath = 'assets/help/test_help.md';
  const packagePath = 'packages/rohd_devtools_widgets/$assetPath';
  const markdown = '''
# Wave Help {{VERSION}}

<!-- tooltip -->

Quick help for {{THING}}

<!-- details -->

## Navigation

| Key | Description |
| --- | --- |
| `F` | Fit to canvas |

First line
second line
''';

  Future<void> pumpUntilTooltipMessage(
    WidgetTester tester,
    String expected,
  ) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      if (tooltip.message == expected) {
        return;
      }
    }
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, expected);
  }

  testWidgets('loads markdown, applies substitutions, and renders dialog',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _MapAssetBundle({packagePath: markdown}),
          child: const MarkdownHelpButton(
            assetPath: assetPath,
            package: 'rohd_devtools_widgets',
            isDark: false,
            label: 'Help',
            substitutions: {'VERSION': '1.2.3', 'THING': 'waveforms'},
          ),
        ),
      ),
    );
    await pumpUntilTooltipMessage(tester, 'Quick help for waveforms');

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Quick help for waveforms',
    );

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(find.text('Wave Help 1.2.3'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('Fit to canvas'), findsOneWidget);
    expect(find.text('First line second line'), findsOneWidget);
  });

  testWidgets('falls back to bare asset path when package asset is unavailable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _MapAssetBundle({assetPath: markdown}),
          child: const MarkdownHelpButton(
            assetPath: assetPath,
            package: 'rohd_devtools_widgets',
            isDark: true,
            labelIcon: Icon(Icons.help_outline),
            substitutions: {'VERSION': '2.0.0', 'THING': 'signals'},
          ),
        ),
      ),
    );
    await pumpUntilTooltipMessage(tester, 'Quick help for signals');

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Quick help for signals',
    );
  });
}

class _MapAssetBundle extends CachingAssetBundle {
  final Map<String, String> assets;

  _MapAssetBundle(this.assets);

  @override
  Future<ByteData> load(String key) async {
    final asset = assets[key];
    if (asset == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(asset)));
  }
}
