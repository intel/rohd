// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_vm_connection_strategy_test.dart
// Tests for platform VM connection strategy dispatch and native validation.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/platform_vm_connection_strategy.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

void main() {
  test('platform strategy resolves to the native IO implementation on VM', () {
    expect(createPlatformVmConnectionStrategy(), isA<IoVmConnectionStrategy>());
    expect(platformVmConnectionStrategy(), isA<IoVmConnectionStrategy>());
  });

  test('IO strategy rejects invalid URI syntax before connecting', () async {
    final strategy = IoVmConnectionStrategy();

    await expectLater(
      strategy.connect('http://[invalid'),
      throwsA(isA<Exception>()),
    );
  });

  test('IO strategy selects the isolate containing the ROHD inspector service',
      () async {
    final vmService = _MockVmService();
    when(vmService.getVM).thenAnswer(
      (_) async => VM(
        isolates: [
          IsolateRef(id: 'isolate-helper'),
          IsolateRef(id: 'isolate-rohd'),
        ],
      ),
    );
    when(() => vmService.getIsolate('isolate-helper')).thenAnswer(
      (_) async => Isolate(
        id: 'isolate-helper',
        libraries: [
          LibraryRef(id: 'lib-helper', uri: 'package:other/main.dart')
        ],
      ),
    );
    when(() => vmService.getIsolate('isolate-rohd')).thenAnswer(
      (_) async => Isolate(
        id: 'isolate-rohd',
        libraries: [
          LibraryRef(
            id: 'lib-rohd',
            uri: 'package:rohd/inspector_service.dart',
          ),
        ],
      ),
    );

    final strategy = IoVmConnectionStrategy(
      connectUri: (uri, log) async {
        expect(uri, 'ws://host:8181/app=/ws');
        return vmService;
      },
      retryDelay: Duration.zero,
    );

    final result = await strategy.connect('http://host:8181/app=/');

    expect(result.vmService, vmService);
    expect(result.isolateId, 'isolate-rohd');
  });

  test('IO strategy falls back to the first isolate when ROHD is not found',
      () async {
    final vmService = _MockVmService();
    when(vmService.getVM).thenAnswer(
      (_) async => VM(isolates: [IsolateRef(id: 'isolate-main')]),
    );
    when(() => vmService.getIsolate('isolate-main')).thenAnswer(
      (_) async => Isolate(
        id: 'isolate-main',
        libraries: [LibraryRef(id: 'lib-main', uri: 'package:app/main.dart')],
      ),
    );

    final strategy = IoVmConnectionStrategy(
      connectUri: (uri, log) async => vmService,
      retryDelay: Duration.zero,
    );

    final result = await strategy.connect('ws://host:8181/app=/ws');

    expect(result.isolateId, 'isolate-main');
  });
}
