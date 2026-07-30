// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// service_manager_bridge_io.dart
// Native implementation for exposing a local DevTools ServiceManager.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:devtools_app_shared/service.dart';
import 'package:vm_service/vm_service.dart' as vm;

/// Native fallback: keep an app-local ServiceManager instance.
final ServiceManager<vm.VmService> serviceManager =
    ServiceManager<vm.VmService>();
