// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_signal_value_source_test.dart
// Tests for VM service signal value source behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_signal_value_source.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _MockVmService extends Mock implements vm.VmService {}

void main() {
  late _MockVmService vmService;
  late StreamController<vm.Event> debugEvents;
  late VmServiceSignalValueSource source;

  setUp(() {
    vmService = _MockVmService();
    debugEvents = StreamController<vm.Event>.broadcast();
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    source = VmServiceSignalValueSource(
      rohdControllerEval: EvalOnDartLibrary(
        'test',
        vmService,
        serviceManager: ServiceManager<vm.VmService>(),
      ),
      evalDisposable: Disposable(),
      vmService: vmService,
    );
  });

  tearDown(() async {
    await source.dispose();
    await debugEvents.close();
  });

  test('reads and remembers a positive current time from the extension',
      () async {
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.currentTime',
        args: any(named: 'args'),
      ),
    ).thenAnswer((_) async => vm.Response()..json = {'currentTime': 42});

    expect(await source.getCurrentTime(), 42);
  });

  test('maps compact extension snapshots into signal data', () async {
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.snapshotCompact',
        args: any(named: 'args'),
      ),
    ).thenAnswer(
      (_) async => vm.Response()
        ..json = {
          'signals': {
            'top.counter': {
              'name': 'counter',
              'value': "8'h2a",
              'width': 8,
            },
          },
        },
    );

    expect(
      await source.getSnapshot(17),
      {
        'top.counter': {
          'name': 'counter',
          'value': "8'h2a",
          'width': 8,
        },
      },
    );
    verify(
      () => vmService.callServiceExtension(
        'ext.rohd.snapshotCompact',
        args: {'time': '17'},
      ),
    ).called(1);
  });

  test('emits updates for pause events and ignores unrelated debug events',
      () async {
    final update = source.updates.first;

    debugEvents
      ..add(vm.Event(kind: 'Resume'))
      ..add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));

    final event = await update;
    expect(event.upToTime, 1);
    expect(event.hasData, isTrue);
    expect(event.reason, vm.EventKind.kPauseBreakpoint);
  });
}
