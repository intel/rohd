// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_version.dart
// Application version from Flutter build metadata.
//
// 2026 November 10
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/browser_window.dart';

/// Version of the running debugger build.
String appVersion = 'unknown';

/// Loads the application version before the debugger UI is started.
Future<void> initAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform(
      baseUrl: kIsWeb ? browserCurrentHref() : null,
    );
    if (info.version.isEmpty) {
      debugPrint('Unable to determine the ROHD Live Debugger version.');
      appVersion = 'unknown';
    } else {
      appVersion = info.version;
    }
  } on Exception catch (error, stackTrace) {
    debugPrint('Unable to determine the ROHD Live Debugger version: $error');
    debugPrintStack(stackTrace: stackTrace);
    appVersion = 'unknown';
  }
}
