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

  VmServiceSignalValueSource createSource({
    Future<vm.Instance> Function(
      String expression, {
      required Disposable? isAlive,
    })? evalInstance,
  }) =>
      VmServiceSignalValueSource(
        rohdControllerEval: EvalOnDartLibrary(
          'test',
          vmService,
          serviceManager: ServiceManager<vm.VmService>(),
        ),
        evalDisposable: Disposable(),
        vmService: vmService,
        evalInstance: evalInstance,
      );

  setUp(() {
    vmService = _MockVmService();
    debugEvents = StreamController<vm.Event>.broadcast();
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    source = createSource();
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

  test('falls back to eval for current time strings and JSON payloads',
      () async {
    await source.dispose();
    final evalValues = <String>['7', '{"currentTime": 12}'];
    source = createSource(
      evalInstance: (expression, {required isAlive}) async => vm.Instance(
        id: 'current-time',
        valueAsString: evalValues.removeAt(0),
      ),
    );
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.currentTime',
        args: any(named: 'args'),
      ),
    ).thenThrow(Exception('extension unavailable'));

    expect(await source.getCurrentTime(), 7);
    expect(await source.getCurrentTime(), 12);
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

  test('maps flat extension snapshot payloads and ignores non-map entries',
      () async {
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.snapshotCompact',
        args: any(named: 'args'),
      ),
    ).thenAnswer(
      (_) async => vm.Response()
        ..json = {
          'top.clk': {
            'name': 'clk',
            'value': '1',
            'width': 1,
          },
          'top.ignored': 'not signal data',
        },
    );

    expect(
      await source.getSnapshot(5),
      {
        'top.clk': {
          'name': 'clk',
          'value': '1',
          'width': 1,
        },
      },
    );
  });

  test('decodes hierarchy snapshots from eval fallback', () async {
    await source.dispose();
    source = createSource(
      evalInstance: (expression, {required isAlive}) async => vm.Instance(
        id: 'hierarchy',
        valueAsString: '''
{
  "name": "top",
  "inputs": {
    "clk": {"value": "1", "width": "1"}
  },
  "outputs": {
    "count": {"value": "3", "width": 8}
  },
  "subModules": [
    {
      "name": "child",
      "inouts": {
        "bus": {"value": "z", "width": "bad"}
      }
    }
  ]
}
''',
      ),
    );
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.snapshotCompact',
        args: any(named: 'args'),
      ),
    ).thenThrow(Exception('extension unavailable'));

    expect(await source.getSnapshot(3), {
      'top.clk': {
        'name': 'clk',
        'value': '1',
        'width': 1,
        'direction': 'Input',
      },
      'top.count': {
        'name': 'count',
        'value': '3',
        'width': 8,
        'direction': 'Output',
      },
      'top.child.bus': {
        'name': 'bus',
        'value': 'z',
        'width': 1,
        'direction': 'Inout',
      },
    });
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

  test('pause updates advance from remembered extension time', () async {
    when(
      () => vmService.callServiceExtension(
        'ext.rohd.currentTime',
        args: any(named: 'args'),
      ),
    ).thenAnswer((_) async => vm.Response()..json = {'currentTime': 42});

    expect(await source.getCurrentTime(), 42);

    final update = source.updates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseInterrupted));

    final event = await update;
    expect(event.upToTime, 43);
    expect(event.reason, vm.EventKind.kPauseInterrupted);
  });
}
