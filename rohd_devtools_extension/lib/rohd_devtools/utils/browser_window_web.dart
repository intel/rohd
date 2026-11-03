// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// browser_window_web.dart
// Web-backed browser/window helpers for opening tabs and reading location.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:web/web.dart' as web;

/// Returns the current browser location.
String browserCurrentHref() => web.window.location.href;

/// Opens [url] in a new browser tab.
void openBrowserTab(String url) {
  web.window.open(url, '_blank');
}
