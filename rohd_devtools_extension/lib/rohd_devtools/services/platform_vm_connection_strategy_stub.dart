// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_vm_connection_strategy_stub.dart
// Stub fallback for [createPlatformVmConnectionStrategy].
// Real implementations live in [io_vm_connection_strategy.dart] and
// [web_vm_connection_strategy.dart] and are selected via conditional
// imports in [platform_vm_connection_strategy.dart].
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

/// Stub that throws when neither `dart:io` nor `dart:js_interop` is available.
/// Returns the platform VM connection strategy, or throws on unsupported
/// targets.
VmConnectionStrategy platformVmConnectionStrategy() {
  throw UnsupportedError(
    'No VmConnectionStrategy available for the current platform.',
  );
}
