// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// extension_manager_bridge.dart
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'extension_manager_bridge_io.dart'
    if (dart.library.js_interop) 'extension_manager_bridge_web.dart';
