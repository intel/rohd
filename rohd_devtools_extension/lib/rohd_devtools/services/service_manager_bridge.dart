// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// service_manager_bridge.dart
// Conditional bridge that exports the platform-specific ServiceManager.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'service_manager_bridge_io.dart'
    if (dart.library.js_interop) 'service_manager_bridge_web.dart';
