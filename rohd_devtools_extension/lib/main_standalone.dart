// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main_standalone.dart
// Unified standalone entry point for both web and native (Linux/macOS/
// Windows) builds.  The platform-appropriate [VmConnectionStrategy] is
// selected via conditional imports in
// `rohd_devtools/services/platform_vm_connection_strategy.dart`.
//
// Run on web:    flutter run -d web-server lib/main_standalone.dart
// Run on Linux:  flutter run -d linux      lib/main_standalone.dart
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/standalone_app_shell.dart';

/// Entry point for the standalone ROHD DevTools app.
void main(List<String> args) {
  _setupLogging();

  final config = StandaloneAppConfig(
    title: 'ROHD DevTools',
    connectionStrategy: createPlatformVmConnectionStrategy(),
  );

  debugPrint(
    '[main_standalone] Starting ROHD DevTools '
    '(${kIsWeb ? "Web" : "Native"})...',
  );
  runApp(StandaloneRohdDevToolsApp(config: config));
}

void _setupLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final ts = record.time.toIso8601String();
    debugPrint(
      '[$ts] [${record.loggerName}] ${record.level.name}: ${record.message}',
    );
    if (record.error != null) {
      debugPrint('  error: ${record.error}');
    }
    if (record.stackTrace != null) {
      debugPrint('  stack: ${record.stackTrace}');
    }
  });
}
