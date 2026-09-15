// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_vm_connection_strategy.dart
// Conditional-import dispatcher that returns the correct
// [VmConnectionStrategy] for the current platform (IO vs. web).
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/services/platform_vm_connection_strategy_stub.dart'
    if (dart.library.io) 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart'
    if (dart.library.js_interop) 'package:rohd_devtools_extension/rohd_devtools/services/web_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

/// Returns the platform-appropriate [VmConnectionStrategy].
///
/// On native (`dart:io`) platforms returns the IO strategy;
/// on web (`dart:js_interop`) platforms returns the web strategy.
VmConnectionStrategy createPlatformVmConnectionStrategy() =>
    platformVmConnectionStrategy();
