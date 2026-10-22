// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// browser_window_stub.dart
// Fallback browser/window helpers for unsupported platforms.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Returns the current browser location when available.
String browserCurrentHref() => Uri.base.toString();

/// Opens [url] in a new browser tab when supported.
void openBrowserTab(String url) {
  // No-op on unsupported platforms.
}
