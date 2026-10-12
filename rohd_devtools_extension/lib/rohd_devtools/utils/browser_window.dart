// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// browser_window.dart
// Conditional export facade for browser/window helpers.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'browser_window_stub.dart'
    if (dart.library.io) 'browser_window_io.dart'
    if (dart.library.js_interop) 'browser_window_web.dart';
