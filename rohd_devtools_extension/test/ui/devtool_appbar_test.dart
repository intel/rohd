// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtool_appbar_test.dart
// Tests for ROHD DevTools app bar and help controls.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_version.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/theme_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtool_appbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/rohd_shell_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/rohd_website_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/standalone_app_shell.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

class _HelpAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key.startsWith('assets/help/')
          ? Future.value(File(key).readAsStringSync())
          : rootBundle.loadString(key, cache: cache);
}

class _UnusedConnectionStrategy extends VmConnectionStrategy {
  @override
  Future<VmConnectionResult> connect(String uri) =>
      throw UnsupportedError('Connection is not used by this test');
}

void main() {
  testWidgets(
    'renders persistent app bar controls and toggles the theme cubit',
    (tester) async {
      final cubit = DevToolsThemeCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: const MaterialApp(
            home: Scaffold(appBar: DevtoolAppBar(hasColorEmoji: false)),
          ),
        ),
      );

      expect(find.text('ROHD DevTools'), findsOneWidget);
      expect(find.text('Licenses'), findsOneWidget);
      expect(find.byType(DevToolsHelpButton), findsOneWidget);
      expect(find.byType(RohdWebsiteButton), findsOneWidget);
      expect(find.byTooltip('Open ROHD website'), findsOneWidget);
      expect(
        tester
            .widget<DevToolsHelpButton>(find.byType(DevToolsHelpButton))
            .hasColorEmoji,
        isFalse,
      );
      expect(find.byTooltip('Switch to light theme'), findsOneWidget);
      expect(const DevtoolAppBar().preferredSize.height, kToolbarHeight);

      await tester.tap(find.byTooltip('Switch to light theme'));
      await tester.pump();

      expect(cubit.state, DevToolsThemeMode.light);
      expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    },
  );

  testWidgets('ROHD logo opens the project website', (tester) async {
    String? openedUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RohdWebsiteButton(openUrl: (url) => openedUrl = url),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open ROHD website'));
    expect(openedUrl, 'https://intel.github.io/rohd-website/');
  });

  testWidgets(
    'passes DevTools help configuration to the markdown help control',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DevToolsHelpButton(isDark: true)),
      );

      final button = tester.widget<MarkdownHelpButton>(
        find.byType(MarkdownHelpButton),
      );
      expect(button.assetPath, 'assets/help/devtools_help.md');
      expect(button.isDark, isTrue);
      expect(button.labelIcon, isNull);
    },
  );

  testWidgets('reports an unknown version when build metadata is empty', (
    tester,
  ) async {
    final previousVersion = appVersion;
    addTearDown(() => appVersion = previousVersion);
    PackageInfo.setMockInitialValues(
      appName: 'ROHD Live Debugger',
      packageName: 'rohd_devtools_extension',
      version: '',
      buildNumber: '',
      buildSignature: '',
    );
    await initAppVersion();

    expect(appVersion, 'unknown');
  });

  testWidgets('shows versioned debugger help with pane sections',
      (tester) async {
    final previousVersion = appVersion;
    addTearDown(() => appVersion = previousVersion);
    PackageInfo.setMockInitialValues(
      appName: 'ROHD Live Debugger',
      packageName: 'rohd_devtools_extension',
      version: '2.3.4',
      buildNumber: '1',
      buildSignature: '',
    );
    await initAppVersion();
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _HelpAssetBundle(),
        child: const MaterialApp(
          home: Scaffold(
            body: DevToolsHelpButton(isDark: true, hasColorEmoji: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<MarkdownHelpButton>(
      find.byType(MarkdownHelpButton),
    );
    expect(button.substitutions, {'VERSION': '2.3.4'});
    expect((button.labelIcon! as Icon).icon, Icons.help_outline);
    await tester.tap(find.byType(MarkdownHelpButton));
    await tester.pumpAndSettle();

    expect(find.text('ROHD Live Debugger v2.3.4 — Help'), findsOneWidget);
    for (final section in [
      'Connection and Setup',
      'Module Tree',
      'Details',
      'Waveform',
      'Schematic',
      'Shell and Pane Help',
      'Tools',
    ]) {
      expect(find.text(section), findsOneWidget);
    }
  });

  testWidgets('bundles ROHD shell help at its configured asset path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RohdShellHelpButton(isDark: true)),
    );

    final button = tester.widget<MarkdownHelpButton>(
      find.byType(MarkdownHelpButton),
    );
    expect(button.assetPath, 'assets/help/rohd_shell_help.md');

    final content = await tester.runAsync(
      () => DefaultAssetBundle.of(
        tester.element(find.byType(RohdShellHelpButton)),
      ).loadString(button.assetPath),
    );
    expect(content, contains('# ROHD Debug Shell Help'));
    expect(content, contains('## Commands'));
  });

  testWidgets('exposes paused controls and the tools menu', (tester) async {
    final cubit = DevToolsThemeCubit();
    addTearDown(cubit.close);
    var resumeRequests = 0;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            appBar: DevtoolAppBar(
              hasColorEmoji: false,
              isPaused: true,
              onPauseResume: () => resumeRequests++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Resume waveform updates'));
    expect(resumeRequests, 1);

    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();

    expect(find.text('Wave Viewer'), findsOneWidget);
    expect(find.text('Schematic Viewer'), findsOneWidget);
    expect(find.text('Standalone Debugger'), findsOneWidget);
    final menuItems = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>));
    expect(
      {for (final item in menuItems) item.value},
      {
        'https://intel.github.io/rohd-wave-viewer/',
        'https://intel.github.io/rohd-schematic-viewer/',
        'https://intel.github.io/rohd/rohd-live-debugger/',
      },
    );
  });

  testWidgets('standalone app bar opens the licenses page', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _HelpAssetBundle(),
        child: StandaloneRohdDevToolsApp(
          config: StandaloneAppConfig(
            connectionStrategy: _UnusedConnectionStrategy(),
          ),
        ),
      ),
    );

    expect(find.byType(RohdWebsiteButton), findsOneWidget);
    expect(find.byTooltip('Open ROHD website'), findsOneWidget);
    await tester.pump();
    Navigator.of(tester.element(find.byType(RohdWebsiteButton))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Licenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
