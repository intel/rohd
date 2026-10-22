// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _MockVmService extends Mock implements vm.VmService {}

const _isolateId = 'isolates/test';
const _libraryId = 'libraries/rohd';

vm.Isolate _isolateWithLibraries(List<vm.LibraryRef> libraries) =>
    vm.Isolate(id: _isolateId, libraries: libraries);

vm.LibraryRef _rohdLibrary() => vm.LibraryRef(
      id: _libraryId,
      uri: 'package:rohd/src/diagnostics/module_services.dart',
    );

vm.Instance _stringResult(String value) => vm.Instance(
      id: 'objects/result',
      kind: vm.InstanceKind.kString,
      valueAsString: value,
    );

void _stubDebugEvents(
  _MockVmService vmService,
  StreamController<vm.Event> debugEvents,
) {
  when(() => vmService.streamListen(any())).thenAnswer(
    (_) async => vm.Success(),
  );
  when(() => vmService.onDebugEvent).thenAnswer((_) => debugEvents.stream);
}

void main() {
  test('decodes fallback waveform and hierarchy transport responses', () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    _stubDebugEvents(vmService, debugEvents);
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([_rohdLibrary()]),
    );
    final expressions = <String>[];
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (invocation) async {
        final expression = invocation.positionalArguments[2] as String;
        expressions.add(expression);
        if (expression.contains('currentTime')) {
          return _stringResult('9');
        }
        if (expression.contains('getSnapshotCompactJSON')) {
          return _stringResult('{"time":9,"v":{"0":"1"}}');
        }
        if (expression.contains('getWaveformsCompactJSON')) {
          return _stringResult(
            '[{"i":"0","d":[{"t":0,"v":"0"},{"t":9,"v":"1"}]}]',
          );
        }
        if (expression.contains('getDataWithTimepointsCompactJSON')) {
          return _stringResult('[{"i":"0","d":[{"t":9,"v":"1"}]}]');
        }
        if (expression.contains('moduleJson')) {
          return _stringResult(
            '{"modules":{"Child":{"ports":{},"cells":{},"netnames":{}}}}',
          );
        }
        if (expression.contains('slimJson')) {
          return _stringResult('{"netlist":{"modules":{"Top":{}}}}');
        }
        throw StateError('Unexpected evaluation: $expression');
      },
    );

    final transport = VmServiceTransport(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(transport.dispose);

    expect(await transport.getCurrentTime(), 9);
    expect(
      (await transport.getSnapshotCompact(9))?['v'],
      {'0': '1'},
    );
    final waveforms = await transport.getWaveformDataCompact(
      signalAddresses: const ['0'],
      addressToSignalId: const {'0': 'top/value'},
    );
    expect(waveforms, hasLength(1));
    expect(waveforms.single.signalId, 'top/value');
    expect(waveforms.single.data.last.time, 9);
    final incremental = await transport.getWaveformDataWithTimepointsCompact(
      signalTimepoints: const {'0': -1},
      addressToSignalId: const {'0': 'top/value'},
    );
    expect(incremental.single.data.single.time, 9);

    expect((await transport.getModuleTree())?['netlist'], isNotNull);
    expect(
      await transport.getModuleNetlist("Requested'Name"),
      contains('Child'),
    );
    expect(
        expressions
            .any((expression) => expression.contains(r"Requested\'Name")),
        isTrue);

    transport
      ..setAddressLookups(
        signalIdToAddress: (signalId) => signalId == 'top/value' ? '0' : null,
        addressToSignalId: (address) => address == '0' ? 'top/value' : null,
      )
      ..trackSignal('top/value');
    final update = transport.liveUpdates.first;
    await transport.resumeFetches();
    expect((await update).incrementalData.single.signalId, 'top/value');
    expect(transport.getLastTrackedTimepoint('top/value'), 9);
    transport.untrackSignal('top/value');
    expect(transport.trackedSignalKeys, isEmpty);
  });

  test('returns unavailable transport values without ROHD libraries', () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    _stubDebugEvents(vmService, debugEvents);
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([
        vm.LibraryRef(id: 'libraries/app', uri: 'package:app/main.dart'),
      ]),
    );
    final transport = VmServiceTransport(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(transport.dispose);

    expect(await transport.getCurrentTime(), isNull);
    expect(await transport.getSnapshotCompact(1), isNull);
    expect(
      await transport.getWaveformDataCompact(
        signalAddresses: const ['0'],
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
    expect(
      await transport.getWaveformDataWithTimepointsCompact(
        signalTimepoints: const {'0': -1},
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
    expect(await transport.getModuleTree(), isNull);
    expect(await transport.getModuleNetlist('Missing'), isNull);
  });

  test('emits compact tracked, paused, and untracked debug updates', () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    _stubDebugEvents(vmService, debugEvents);
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([_rohdLibrary()]),
    );
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
    final transport = VmServiceTransport(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(transport.dispose);
    await Future<void>.delayed(Duration.zero);
    transport
      ..setAddressLookups(
        signalIdToAddress: (signalId) => signalId == 'top/value' ? '0' : null,
        addressToSignalId: (address) => address == '0' ? 'top/value' : null,
      )
      ..trackSignal('top/value');

    final trackedUpdate = transport.liveUpdates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final first = await trackedUpdate;
    expect(first.incrementalData.single.signalId, 'top/value');
    expect(first.upToTime, 10);
    expect(transport.getLastTrackedTimepoint('top/value'), 10);

    currentTime = 20;
    transport.pauseFetches();
    final pausedUpdate = transport.liveUpdates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final paused = await pausedUpdate;
    expect(paused.incrementalData, isEmpty);
    expect(paused.upToTime, 20);

    await transport.resumeFetches();
    transport.untrackAllSignals();
    currentTime = 30;
    final untrackedUpdate = transport.liveUpdates.first;
    debugEvents.add(vm.Event(kind: vm.EventKind.kPauseBreakpoint));
    final untracked = await untrackedUpdate;
    expect(untracked.incrementalData, isEmpty);
    expect(untracked.upToTime, 30);
  });

  test('falls back to a main library and resolves truncated VM strings',
      () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    _stubDebugEvents(vmService, debugEvents);
    const mainLibraryId = 'libraries/main';
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([
        _rohdLibrary(),
        vm.LibraryRef(id: mainLibraryId, uri: 'dart:main'),
      ]),
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
    final transport = VmServiceTransport(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(transport.dispose);

    expect(await transport.getCurrentTime(), 42);
    verify(() => vmService.evaluate(_isolateId, mainLibraryId, any()))
        .called(1);
    verify(() => vmService.getObject(_isolateId, 'objects/truncated'))
        .called(1);
  });

  test('returns unavailable values for malformed and rejected responses',
      () async {
    final vmService = _MockVmService();
    final debugEvents = StreamController<vm.Event>.broadcast();
    addTearDown(debugEvents.close);
    _stubDebugEvents(vmService, debugEvents);
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([_rohdLibrary()]),
    );
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (invocation) async {
        final expression = invocation.positionalArguments[2] as String;
        if (expression.contains('slimJson')) {
          return vm.Success();
        }
        if (expression.contains('moduleJson')) {
          return _stringResult('null');
        }
        return _stringResult('not JSON');
      },
    );
    final transport = VmServiceTransport(
      vmService: vmService,
      isolateId: _isolateId,
    );
    addTearDown(transport.dispose);

    expect(await transport.getCurrentTime(), isNull);
    expect(await transport.getSnapshotCompact(1), isNull);
    expect(
      await transport.getWaveformDataCompact(
        signalAddresses: const ['0'],
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
    expect(
      await transport.getWaveformDataWithTimepointsCompact(
        signalTimepoints: const {'0': -1},
        addressToSignalId: const {'0': 'top/value'},
      ),
      isEmpty,
    );
    expect(await transport.getModuleTree(), isNull);
    expect(await transport.getModuleNetlist('Missing'), isNull);
  });
}
