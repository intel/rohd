// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_dtd_connection_stub.dart
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// DTD connection exposed by DevTools, unavailable on non-web platforms.
final ValueListenable<DartToolingDaemon?> devToolsDtdConnection =
    ValueNotifier<DartToolingDaemon?>(null);

/// VM service exposed by DevTools, unavailable on non-web platforms.
VmService? get devToolsVmService => null;

/// Main isolate exposed by DevTools, unavailable on non-web platforms.
String? get devToolsMainIsolateId => null;
