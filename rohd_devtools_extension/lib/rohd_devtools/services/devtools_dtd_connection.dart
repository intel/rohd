// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_dtd_connection.dart
// Platform-independent DevTools DTD connection export.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'devtools_dtd_connection_stub.dart'
    if (dart.library.js_interop) 'devtools_dtd_connection_web.dart';
