// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// extension_manager_bridge.dart
// Platform-independent extension manager bridge export.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'extension_manager_bridge_io.dart'
    if (dart.library.js_interop) 'extension_manager_bridge_web.dart';
