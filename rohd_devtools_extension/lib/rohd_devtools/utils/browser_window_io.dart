// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// browser_window_io.dart
// IO-backed browser/window helpers for desktop platforms.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:io';

/// Returns the current browser location when available.
String browserCurrentHref() => Uri.base.toString();

/// Opens [url] using the platform default browser.
void openBrowserTab(String url) {
  final uri = Uri.parse(url);
  if (Platform.isLinux) {
    unawaited(Process.start('xdg-open', <String>[uri.toString()]));
    return;
  }
  if (Platform.isMacOS) {
    unawaited(Process.start('open', <String>[uri.toString()]));
    return;
  }
  if (Platform.isWindows) {
    unawaited(
      Process.start('cmd', <String>['/c', 'start', '', uri.toString()]),
    );
  }
}
