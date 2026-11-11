// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_page_test.dart
// Tests for the top-level ROHD DevTools page composition.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
// The DevTools host uses Flutter's MaterialApp, not material_ui's.
// ignore: migrate_design_widgets
import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/third_party_license_registry.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

import '../modules/tree_structure/fixtures/tree_model.stub.dart';

void main() {
  testWidgets('renders in the Flutter Material DevTools host', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const flutter_material.MaterialApp(
        home: RohdDevToolsPage(manageServiceManager: false),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Search Modules'), findsOneWidget);
  });

  testWidgets('opens and closes licenses in the Flutter DevTools host', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const flutter_material.MaterialApp(
        home: RohdDevToolsPage(manageServiceManager: false),
      ),
    );
    await tester.pump();

    registerBundledThirdPartyLicenses();
    final licenses = await tester.runAsync(
      () async => LicenseRegistry.licenses.toList(),
    );
    expect(
      licenses!.expand((license) => license.packages),
      containsAll(['ELK JavaScript layout engine', 'Wellen waveform bridge']),
    );
    for (final entry in licenses.where(
      (license) => license.packages.any(
        (package) =>
            package == 'ELK JavaScript layout engine' ||
            package == 'Wellen waveform bridge',
      ),
    )) {
      expect(
        entry.paragraphs.map((paragraph) => paragraph.text).join('\n'),
        isNot(contains('Unable to load bundled license text')),
      );
    }

    await tester.tap(find.text('Licenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Licenses'), findsWidgets);
    expect(
      Theme.of(tester.element(find.byType(LicensePage))).brightness,
      Brightness.dark,
    );
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TreeStructurePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('license page preserves the embedded light theme and locale', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const flutter_material.MaterialApp(
        locale: Locale('en', 'US'),
        home: RohdDevToolsPage(
          manageServiceManager: false,
          hostThemeMode: DevToolsThemeMode.light,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Licenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final licenseContext = tester.element(find.byType(LicensePage));
    expect(Theme.of(licenseContext).brightness, Brightness.light);
    expect(Localizations.localeOf(licenseContext), const Locale('en', 'US'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('follows changes to the Flutter DevTools host theme', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget host(Brightness brightness) => flutter_material.MaterialApp(
          theme: brightness == Brightness.dark
              ? flutter_material.ThemeData.dark()
              : flutter_material.ThemeData.light(),
          home: flutter_material.Builder(
            builder: (context) => RohdDevToolsPage(
              manageServiceManager: false,
              hostThemeMode: flutter_material.Theme.of(context).brightness ==
                      Brightness.dark
                  ? DevToolsThemeMode.dark
                  : DevToolsThemeMode.light,
            ),
          ),
        );

    Brightness pageBrightness() =>
        Theme.of(tester.element(find.byType(TreeStructurePage))).brightness;

    await tester.pumpWidget(host(Brightness.light));
    await tester.pump();
    final treeState = tester.state(find.byType(TreeStructurePage));
    expect(pageBrightness(), Brightness.light);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pump();
    expect(pageBrightness(), Brightness.dark);

    await tester.pumpWidget(host(Brightness.dark));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(pageBrightness(), Brightness.dark);
    await tester.pumpWidget(host(Brightness.light));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(pageBrightness(), Brightness.light);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    expect(tester.state(find.byType(TreeStructurePage)), same(treeState));
  });

  testWidgets('builds the extension module and toggles its theme', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: RohdDevToolsPage(manageServiceManager: false)),
    );
    await tester.pump();

    expect(find.byType(RohdExtensionModule), findsOneWidget);
    expect(find.byType(DevtoolAppBar), findsOneWidget);
    expect(find.byType(TreeStructurePage), findsOneWidget);
    expect(find.text('ROHD DevTools'), findsOneWidget);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    final module = HierarchyOccurrenceStub.simpleHierarchyOccurrence;
    tester
        .element(find.byType(TreeStructurePage))
        .read<DevToolsHierarchyCubit>()
      ..loadFromNode(module)
      ..selectModule(module);
    await tester.pump();
    expect(find.byType(SignalDetailsCard), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(TreeStructurePage))).brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(SignalDetailsCard))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar).first).backgroundColor,
      DarkThemeColors.appBarBackground,
    );

    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pump();

    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(TreeStructurePage))).brightness,
      Brightness.light,
    );
    expect(
      Theme.of(tester.element(find.byType(SignalDetailsCard))).brightness,
      Brightness.light,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar).first).backgroundColor,
      LightThemeColors.appBarBackground,
    );
    expect(
      tester.widget<DevToolsHelpButton>(find.byType(DevToolsHelpButton)).isDark,
      isFalse,
    );

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pump();
    expect(
      Theme.of(tester.element(find.byType(TreeStructurePage))).brightness,
      Brightness.dark,
    );
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
  });

  testWidgets('provides all page-owned DevTools cubits', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: RohdDevToolsPage(manageServiceManager: false)),
    );
    await tester.pump();

    final context = tester.element(find.byType(RohdExtensionModule));
    expect(context.read<DevToolsThemeCubit>(), isA<DevToolsThemeCubit>());
    expect(context.read<RohdServiceCubit>(), isA<RohdServiceCubit>());
    expect(context.read<TreeSearchTermCubit>(), isA<TreeSearchTermCubit>());
    expect(
      context.read<DevToolsHierarchyCubit>(),
      isA<DevToolsHierarchyCubit>(),
    );
    expect(
      context.read<SignalSearchTermCubit>(),
      isA<SignalSearchTermCubit>(),
    );
    expect(context.read<DetailsTabCubit>(), isA<DetailsTabCubit>());
    expect(context.read<SnapshotCubit>(), isA<SnapshotCubit>());
  });
}
