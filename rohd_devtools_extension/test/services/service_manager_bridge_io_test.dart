// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// service_manager_bridge_io_test.dart
// Tests for the native ServiceManager bridge.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:devtools_app_shared/service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/service_manager_bridge_io.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  test('exposes an app-local VM service manager', () {
    expect(serviceManager, isA<ServiceManager<vm.VmService>>());
    expect(serviceManager.connectedState.value.connected, isFalse);
  });
}
