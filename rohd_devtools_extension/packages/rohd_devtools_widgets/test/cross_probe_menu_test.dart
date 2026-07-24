// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_menu_test.dart
// Tests for cross-probe source navigation menu helpers.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  test('encodes, decodes, and labels source menu values', () {
    expect(gotoSourceMenuValue(RohdSourceFormat.rohd), 'goto_source:rohd');
    expect(
      gotoSourceFormatFromValue('goto_source:sv'),
      RohdSourceFormat.sv,
    );
    expect(gotoSourceFormatFromValue(null), isNull);
    expect(gotoSourceFormatFromValue('other'), isNull);
    expect(gotoSourceFormatFromValue('goto_source:missing'), isNull);

    expect(gotoSourceShortName(RohdSourceFormat.rohd), 'ROHD');
    expect(gotoSourceShortName(RohdSourceFormat.sv), 'SV');
    expect(gotoSourceShortName(RohdSourceFormat.sc), 'SystemC');
    expect(gotoSourceShortName(RohdSourceFormat.fst), 'Waveform');
    expect(
      gotoSourceMenuLabel(RohdSourceFormat.rohd),
      'Go to ROHD Source',
    );
    expect(
      gotoSourceMenuLabel(RohdSourceFormat.sv, count: 3),
      'Go to SV Source (3)',
    );
  });

  test('resolves default and exact navigable formats', () {
    expect(resolveNavigableFormats(null), kDefaultNavigableFormats);
    expect(
      resolveNavigableFormats(const RohdModuleInfo(extensionAvailable: false)),
      kDefaultNavigableFormats,
    );
    expect(
      resolveNavigableFormats(
        const RohdModuleInfo(extensionAvailable: true, error: 'not ready'),
      ),
      kDefaultNavigableFormats,
    );
    expect(
      resolveNavigableFormats(
        const RohdModuleInfo(
          extensionAvailable: true,
          formats: {
            RohdSourceFormat.rohd: RohdFormatInfo(
              available: true,
              fileFound: false,
            ),
            RohdSourceFormat.sv: RohdFormatInfo(
              available: false,
              fileFound: true,
            ),
          },
        ),
      ),
      isEmpty,
    );

    final info = RohdModuleInfo(
      extensionAvailable: true,
      formats: {
        RohdSourceFormat.rohd: const RohdFormatInfo(
          available: true,
          fileFound: true,
        ),
        RohdSourceFormat.sc: const RohdFormatInfo(
          available: true,
          fileFound: true,
        ),
        RohdSourceFormat.fst: const RohdFormatInfo(
          available: true,
          fileFound: true,
        ),
      },
    );

    expect(
      resolveNavigableFormats(info),
      [RohdSourceFormat.rohd, RohdSourceFormat.sc],
    );
  });

  testWidgets('builds popup menu items with encoded values and custom icons',
      (tester) async {
    final items = buildGotoSourceMenuItems(
      formats: [RohdSourceFormat.rohd, RohdSourceFormat.sv],
      count: 2,
      showIcons: true,
      iconBuilder: (format, {double size = 18}) => Icon(
        Icons.code,
        key: ValueKey(format),
        size: size,
      ),
    );

    expect(items, hasLength(2));
    expect(items[0].value, 'goto_source:rohd');
    expect(items[1].value, 'goto_source:sv');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [for (final item in items) item.child!],
          ),
        ),
      ),
    );

    expect(find.text('Go to ROHD Source (2)'), findsOneWidget);
    expect(find.text('Go to SV Source (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey(RohdSourceFormat.rohd)), findsOneWidget);
    expect(find.byKey(const ValueKey(RohdSourceFormat.sv)), findsOneWidget);
  });

  testWidgets('builds rows, disabled menu items, and no-icon source items',
      (tester) async {
    final disabled = buildRohdPopupMenuItem<String>(
      value: 'disabled',
      icon: const Icon(Icons.block),
      label: 'Disabled item',
      enabled: false,
      height: 40,
    );
    final noIconItems = buildGotoSourceMenuItems(
      formats: [RohdSourceFormat.sc],
      showIcons: false,
      textStyle: const TextStyle(fontSize: 11),
    );

    expect(disabled.enabled, isFalse);
    expect(disabled.height, 40);
    expect(noIconItems.single.value, 'goto_source:sc');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              disabled.child!,
              noIconItems.single.child!,
              sourcePopupMenuRow(
                icon: const Icon(Icons.timeline),
                label: 'A very long source navigation item label',
                iconSlotWidth: 30,
                gap: 4,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Disabled item'), findsOneWidget);
    expect(find.text('Go to SystemC Source'), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.byIcon(Icons.timeline), findsOneWidget);
  });

  testWidgets('source format icons cover strips, aliases, and waveform icon',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              sourceFormatMenuIcon(RohdSourceFormat.fst, size: 21),
              sourceFormatIcon(RohdSourceFormat.fst, size: 22),
              sourceFormatIconStrip(
                formats: const [
                  RohdSourceFormat.rohd,
                  RohdSourceFormat.sv,
                  RohdSourceFormat.sc,
                ],
                size: 13,
                gap: 5,
                iconBuilder: (format, {double size = 16}) => Icon(
                  Icons.code,
                  key: ValueKey('strip-${format.name}'),
                  size: size,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.timeline), findsNWidgets(2));
    expect(find.byKey(const ValueKey('strip-rohd')), findsOneWidget);
    expect(find.byKey(const ValueKey('strip-sv')), findsOneWidget);
    expect(find.byKey(const ValueKey('strip-sc')), findsOneWidget);
  });
}
