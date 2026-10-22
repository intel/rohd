// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_waveform_data_source.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _MockVmService extends Mock implements vm.VmService {}

const _isolateId = 'isolates/test';
const _libraryId = 'libraries/rohd';

vm.Isolate _rohdIsolate() => vm.Isolate(
      id: _isolateId,
      libraries: [
        vm.LibraryRef(
          id: _libraryId,
          uri: 'package:rohd/src/diagnostics/module_services.dart',
        ),
      ],
    );

vm.Instance _stringResult(String value) => vm.Instance(
      id: 'objects/result',
      kind: vm.InstanceKind.kString,
      valueAsString: value,
    );

void main() {
  test('emits compact tracked, paused, and untracked debug updates', () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    when(() => vmService.streamListen(any())).thenAnswer(
      (_) async => vm.Success(),
    );
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    when(() => vmService.getIsolate(_isolateId))
        .thenAnswer((_) async => _rohdIsolate());
    var currentTime = 10;
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (invocation) async {
        final expression = invocation.positionalArguments[2] as String;
        if (expression.contains('currentTime')) {
          return _stringResult('$currentTime');
        }
        if (expression.contains('getDataWithTimepointsCompactJSON')) {
          return _stringResult(
            '[{"i":"0","d":[{"t":$currentTime,"v":"1"}]}]',
          );
        }
        throw StateError('Unexpected evaluation: $expression');
      },
    );
    final source = VmServiceWaveformDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(source.dispose);
    await Future<void>.delayed(Duration.zero);
    source
      ..setAddressLookups(
        signalIdToAddress: (signalId) => signalId == 'top/value' ? '0' : null,
        addressToSignalId: (address) => address == '0' ? 'top/value' : null,
      )
      ..trackSignal('top/value');

    final trackedUpdate = source.liveUpdates.first;
    debugEvents
      ..add(vm.Event(kind: 'Resume'))
      ..add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final first = await trackedUpdate;
    expect(first.incrementalData.single.signalId, 'top/value');
    expect(first.upToTime, 10);
    expect(source.getLastTrackedTimepoint('top/value'), 10);

    currentTime = 20;
    source.pauseFetches();
    final pausedUpdate = source.liveUpdates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final paused = await pausedUpdate;
    expect(paused.incrementalData, isEmpty);
    expect(paused.upToTime, 20);

    await source.resumeFetches();
    source.untrackAllSignals();
    currentTime = 30;
    final untrackedUpdate = source.liveUpdates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final untracked = await untrackedUpdate;
    expect(untracked.incrementalData, isEmpty);
    expect(untracked.upToTime, 30);
  });

  test('returns unavailable values when no ROHD library is present', () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    when(() => vmService.streamListen(any())).thenAnswer(
      (_) async => vm.Success(),
    );
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => vm.Isolate(
        id: _isolateId,
        libraries: [
          vm.LibraryRef(id: 'libraries/app', uri: 'package:app/main.dart'),
        ],
      ),
    );
    final source = VmServiceWaveformDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(source.dispose);

    expect(await source.getCurrentTime(), isNull);
    expect(await source.getSnapshotCompact(1), isNull);
    expect(
      await source.getWaveformDataWithTimepoints(
        signalTimepoints: const {'top/value': -1},
      ),
      isEmpty,
    );
    expect(
      await source.getWaveformDataWithTimepointsCompact(
        signalTimepoints: const {'0': -1},
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
  });

  test('falls back to a main library and resolves a truncated current time',
      () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    when(() => vmService.streamListen(any())).thenAnswer(
      (_) async => vm.Success(),
    );
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    const mainLibraryId = 'libraries/main';
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => vm.Isolate(
        id: _isolateId,
        libraries: [
          vm.LibraryRef(
            id: _libraryId,
            uri: 'package:rohd/src/diagnostics/module_services.dart',
          ),
          vm.LibraryRef(id: mainLibraryId, uri: 'dart:main'),
        ],
      ),
    );
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenThrow(
      Exception("Undefined name 'WaveformService'"),
    );
    when(() => vmService.evaluate(_isolateId, mainLibraryId, any())).thenAnswer(
      (_) async => vm.InstanceRef(
        id: 'objects/truncated',
        valueAsString: '4',
        valueAsStringIsTruncated: true,
      ),
    );
    when(() => vmService.getObject(_isolateId, 'objects/truncated')).thenAnswer(
      (_) async => _stringResult('42'),
    );
    final source = VmServiceWaveformDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(source.dispose);

    expect(await source.getCurrentTime(), 42);
    verify(() => vmService.evaluate(_isolateId, mainLibraryId, any()))
        .called(1);
    verify(() => vmService.getObject(_isolateId, 'objects/truncated'))
        .called(1);
  });

  test('returns unavailable values for malformed and disposed responses',
      () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    when(() => vmService.streamListen(any())).thenAnswer(
      (_) async => vm.Success(),
    );
    when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
    when(() => vmService.getIsolate(_isolateId))
        .thenAnswer((_) async => _rohdIsolate());
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (_) async => _stringResult('not JSON'),
    );
    final source = VmServiceWaveformDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );

    expect(await source.getCurrentTime(), isNull);
    expect(await source.getSnapshotCompact(1), isNull);
    expect(
      await source.getWaveformDataCompact(
        signalAddresses: const ['0'],
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
    expect(
      await source.getWaveformDataWithTimepointsCompact(
        signalTimepoints: const {'0': -1},
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );

    await source.dispose();
    expect(source.isConnected, isFalse);
    expect(await source.getCurrentTime(), isNull);
    expect(await source.getSnapshotCompact(1), isNull);
  });
}
