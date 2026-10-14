// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_cubit_test.dart
// Tests for ROHD service cubit behavior without a VM service.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/rohd_service_cubit.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _MockVmService extends Mock implements vm.VmService {}

void main() {
  test('configures a standalone service and finds the ROHD isolate', () async {
    final vmService = _MockVmService();
    const rohdIsolateId = 'isolates/rohd';
    final rohdIsolate = vm.IsolateRef(
      id: rohdIsolateId,
      name: 'rohd application',
    );
    final vmInfo = vm.VM(
      version: '3.6.0',
      isolates: [
        vm.IsolateRef(id: 'isolates/runner', name: 'test runner'),
        rohdIsolate,
      ],
    );
    final inspectorLibrary = vm.LibraryRef(
      id: 'libraries/rohd-inspector',
      uri: 'package:rohd/src/diagnostics/inspector_service.dart',
    );
    final dartIoLibrary = vm.LibraryRef(
      id: 'libraries/dart-io',
      uri: 'dart:io',
    );
    const hierarchyPayload = '''
      {"name":"top","inputs":{},"outputs":{},"subModules":[]}
    ''';

    when(() => vmService.wsUri).thenReturn('ws://host:8181/app=/ws');
    when(vmService.getVM).thenAnswer((_) async => vmInfo);
    when(() => vmService.onIsolateEvent)
        .thenAnswer((_) => const Stream<vm.Event>.empty());
    when(() => vmService.onDebugEvent)
        .thenAnswer((_) => const Stream<vm.Event>.empty());
    when(() => vmService.onExtensionEvent)
        .thenAnswer((_) => const Stream<vm.Event>.empty());
    when(() => vmService.onEvent(any()))
        .thenAnswer((_) => const Stream<vm.Event>.empty());
    when(() => vmService.streamListen(any()))
        .thenAnswer((_) async => vm.Success());
    when(() => vmService.getIsolate('isolates/runner')).thenAnswer(
      (_) async => vm.Isolate(
        id: 'isolates/runner',
        name: 'test runner',
        libraries: [dartIoLibrary],
      ),
    );
    when(() => vmService.getIsolate(rohdIsolateId)).thenAnswer(
      (_) async => vm.Isolate(
        id: rohdIsolateId,
        name: 'rohd application',
        libraries: [dartIoLibrary, inspectorLibrary],
      ),
    );
    when(
      () => vmService.evaluate(
        rohdIsolateId,
        inspectorLibrary.id!,
        any(),
        scope: any(named: 'scope'),
        disableBreakpoints: any(named: 'disableBreakpoints'),
      ),
    ).thenAnswer(
      (_) async => vm.Instance(
        id: 'objects/hierarchy',
        kind: vm.InstanceKind.kString,
        valueAsString: hierarchyPayload,
      ),
    );
    when(
      () => vmService.getObject(
        rohdIsolateId,
        'objects/hierarchy',
        offset: any(named: 'offset'),
        count: any(named: 'count'),
      ),
    ).thenAnswer(
      (_) async => vm.Instance(
        id: 'objects/hierarchy',
        kind: vm.InstanceKind.kString,
        valueAsString: hierarchyPayload,
      ),
    );

    final cubit = RohdServiceCubit(manageServiceManager: false);
    addTearDown(cubit.close);

    await cubit.configureStandaloneVmService(vmService, rohdIsolateId);
    await cubit.evalModuleTree();

    expect(cubit.rohdIsolateId, rohdIsolateId);
    expect(cubit.treeService, isNotNull);
    expect(cubit.state, isA<RohdServiceLoaded>());
    expect((cubit.state as RohdServiceLoaded).treeModel?.name, 'top');
    verify(vmService.getVM).called(greaterThanOrEqualTo(2));
    verify(() => vmService.getIsolate(rohdIsolateId))
        .called(greaterThanOrEqualTo(1));
  });

  test('returns a loaded null tree when no VM service is configured', () async {
    final cubit = RohdServiceCubit(manageServiceManager: false);
    addTearDown(cubit.close);
    final emittedStates = cubit.stream.take(4).toList();

    await cubit.evalModuleTree();
    await cubit.refreshModuleTree();

    expect(
      await emittedStates,
      [
        isA<RohdServiceLoading>(),
        const RohdServiceLoaded(null),
        isA<RohdServiceLoading>(),
        const RohdServiceLoaded(null),
      ],
    );
    expect(cubit.state, const RohdServiceLoaded(null));
    expect(cubit.treeService, isNull);
    expect(cubit.signalValueSource, isNull);
    expect(cubit.rohdIsolateId, isNull);
  });
}
