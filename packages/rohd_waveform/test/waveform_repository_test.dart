// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_repository_test.dart
// Unit tests for repository-backed waveform loading and caching.
//
// 2026 July 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('SignalWaveformRepository', () {
    late SignalOccurrence clk;
    late SignalOccurrence bus;
    late HierarchyOccurrence top;
    late _FakeSignalWaveformApi api;
    late SignalWaveformRepository repository;

    setUp(() {
      clk = SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
        portIndex: 0,
      );
      bus = SignalOccurrence(name: 'bus', width: 4);
      top = HierarchyOccurrence(name: 'top', signals: [clk, bus]);
      api = _FakeSignalWaveformApi({
        'top/clk': [Data(time: 0, value: '0'), Data(time: 5, value: '1')],
        'top.clk': [Data(time: 2, value: '1'), Data(time: 7, value: '0')],
        'top/bus': [
          Data(time: 0, value: "4'b1010"),
          Data(time: 5, value: "4'b1011"),
          Data(time: 10, value: "4'b0011"),
        ],
      });
      repository = SignalWaveformRepository(signalWaveformApi: api)
        ..buildSignalCacheFromHierarchy([top]);
    });

    test('builds signal cache and loads waveforms by hierarchy path', () async {
      expect(repository.cachedSignalIds, containsAll(['top/clk', 'top/bus']));
      expect(repository.getSignal(clk.address!), same(clk));
      expect(repository.getWaveform(clk.address!), isEmpty);

      final loaded = await repository.loadAndAppendWaveformData(
        signalIds: ['top/clk'],
      );

      expect(api.requests, hasLength(1));
      expect(api.requests.single.signalIds, ['top/clk']);
      expect(api.requests.single.startTime, isNull);
      expect(api.requests.single.endTime, isNull);
      expect(loaded.single.signalId, 'top/clk');
      expect(repository.getWaveform(clk.address!)!.data, hasLength(2));
      expect(repository.getWaveformById('top/clk')!.getValueByTime(5), '1');
    });

    test('loads dot-separated waveform IDs into slash-path cache', () async {
      final loaded = await repository.loadAndAppendWaveformData(
        signalIds: ['top.clk'],
      );

      expect(loaded.single.signalId, 'top.clk');
      expect(repository.getWaveform(clk.address!)!.data.map((d) => d.time), [
        2,
        7,
      ]);
      expect(repository.getWaveformById('top/clk')!.getValueByTime(7), '0');
      expect(
        repository.getWaveformById('top.clk'),
        same(repository.getWaveformById('top/clk')),
      );
    });

    test('forwards requested time windows to the API', () async {
      await repository.loadAndAppendWaveformData(
        signalIds: ['top/clk', 'top/bus'],
        startTime: 5,
        endTime: 10,
      );

      expect(api.requests, hasLength(1));
      expect(api.requests.single.signalIds, ['top/clk', 'top/bus']);
      expect(api.requests.single.startTime, 5);
      expect(api.requests.single.endTime, 10);
    });

    test('delegates current time and slim module expansion to the API',
        () async {
      expect(await repository.getCurrentTime(), 42);

      await repository.expandAllSlimModules();

      expect(api.currentTimeCalls, 1);
      expect(api.expandAllSlimModulesCalls, 1);
    });

    test('waits for apiReady before reading current time', () async {
      final ready = Completer<void>();
      api.isLoadedValue = false;
      repository = SignalWaveformRepository(
        signalWaveformApi: api,
        apiReady: ready.future,
      );

      final currentTime = repository.getCurrentTime();
      await Future<void>.delayed(Duration.zero);
      expect(api.currentTimeCalls, 0);

      ready.complete();
      expect(await currentTime, 42);
      expect(api.currentTimeCalls, 1);
    });

    test('setSignalWaveformApi clears caches and uses replacement API',
        () async {
      await repository.loadAndAppendWaveformData(signalIds: ['top/clk']);
      expect(repository.getSignal(clk.address!), same(clk));
      expect(repository.getWaveform(clk.address!)!.data, isNotEmpty);

      final replacementApi = _FakeSignalWaveformApi({
        'top/clk': [Data(time: 20, value: '1')],
      });
      repository.setSignalWaveformApi(replacementApi);

      expect(repository.api, same(replacementApi));
      expect(repository.cachedSignalIds, isEmpty);
      expect(repository.getSignal(clk.address!), isNull);
      expect(repository.getWaveform(clk.address!), isNull);

      repository.buildSignalCacheFromHierarchy([top]);
      await repository.loadAndAppendWaveformData(signalIds: ['top/clk']);

      expect(replacementApi.requests, hasLength(1));
      expect(repository.getWaveform(clk.address!)!.data.single.time, 20);
    });

    test('appends and clears waveform cache entries', () {
      expect(
        repository.appendDataToSignal(
          'top/clk',
          [Data(time: 5, value: '1'), Data(time: 0, value: '0')],
          sortByTime: true,
        ),
        isTrue,
      );
      expect(repository.getWaveform(clk.address!)!.data.map((d) => d.time), [
        0,
        5,
      ]);

      expect(repository.clearWaveformData(clk.address!), isTrue);
      expect(repository.getWaveform(clk.address!)!.data, isEmpty);
      expect(
          repository.clearWaveformData(const OccurrenceAddress([99])), isFalse);
    });

    test('keeps unresolved waveform IDs in sub-field cache', () {
      expect(
        repository.appendDataToSignal(
          'top/bus#b[0]',
          [Data(time: 0, value: '0')],
        ),
        isTrue,
      );

      expect(
          repository.getWaveformById('top/bus#b[0]')!.data.single.value, '0');

      repository.clearAllWaveformData();
      expect(repository.getWaveformById('top/bus#b[0]'), isNull);
      expect(repository.getSignal(clk.address!), same(clk));
    });

    test('selected module helpers expose signal metadata and waveforms', () {
      repository.clearAllWaveformData();

      final signals = repository.getSignalsBySelectedModule(top);
      final waveforms = repository.getWaveformsBySelectedModule(top);

      expect(signals, [clk, bus]);
      expect(waveforms.map((w) => w.signalId), ['top/clk', 'top/bus']);
      expect(repository.getWaveform(clk.address!), same(waveforms.first));
    });

    test('can stream without appending to cached waveforms', () async {
      api.streamResponses = [
        WaveformData(
          signalId: 'top/clk',
          data: [Data(time: 10, value: '0')],
        ),
      ];

      final streamed = await repository.streamWaveformData(
          signalIds: ['top/clk'], appendToSignals: false).toList();

      expect(streamed, hasLength(1));
      expect(repository.getWaveform(clk.address!)!.data, isEmpty);
    });

    test('streams unresolved waveform IDs into the computed cache', () async {
      api.streamResponses = [
        WaveformData(
          signalId: 'top/bus#b[0]',
          data: [Data(time: 0, value: '0')],
        ),
        WaveformData(
          signalId: 'top/bus#b[0]',
          data: [Data(time: 5, value: '1')],
        ),
      ];

      await repository
          .streamWaveformData(signalIds: ['top/bus#b[0]']).drain<void>();

      expect(
        repository.getWaveformById('top/bus#b[0]')!.data.map((d) => d.value),
        ['0', '1'],
      );
    });

    test('repository signal data service wraps cached waveforms', () async {
      final service = RepositorySignalDataService(repository);

      final uncached = await service.getSignalData(
        SignalOccurrence(name: 'detached', width: 1),
      );
      expect(uncached.data, isEmpty);
      expect(uncached.metadata, containsPair('cached', false));

      await repository.loadAndAppendWaveformData(signalIds: ['top/clk']);
      final cached = await service.getSignalData(clk);

      expect(cached.port, same(clk));
      expect(cached.data.map((d) => d.value), ['0', '1']);
      expect(cached.metadata, containsPair('cached', true));
      expect(cached.metadata, containsPair('path', 'top/clk'));
    });

    test('streams waveform data and appends it to the cache', () async {
      api.streamResponses = [
        WaveformData(
          signalId: 'top/clk',
          data: [Data(time: 10, value: '0')],
        ),
        WaveformData(
          signalId: 'top/clk',
          data: [Data(time: 15, value: '1')],
        ),
      ];

      final streamed = await repository
          .streamWaveformData(signalIds: ['top/clk'], startTime: 10).toList();

      expect(streamed, hasLength(2));
      expect(api.streamRequests, hasLength(1));
      expect(api.streamRequests.single.signalIds, ['top/clk']);
      expect(api.streamRequests.single.startTime, 10);
      expect(repository.getWaveform(clk.address!)!.data.map((d) => d.time), [
        10,
        15,
      ]);
    });

    test('synthesizes bit-slice waveform data from parent signal', () async {
      final synthesized = await repository.getWaveformData(
        signalIds: ['top/bus#b[1:0]'],
      );

      expect(api.requests, hasLength(1));
      expect(api.requests.single.signalIds, ['top/bus']);
      expect(api.requests.single.startTime, isNull);
      expect(api.requests.single.endTime, isNull);
      expect(synthesized.single.signalId, 'top/bus#b[1:0]');
      expect(synthesized.single.isComputed, isTrue);
      expect(synthesized.single.data.map((d) => d.time), [0, 5]);
      expect(synthesized.single.data.map((d) => d.value), ["2'h2", "2'h3"]);
    });

    test('appends range-loaded computed waveforms to their cache', () async {
      await repository.loadAndAppendWaveformData(
        signalIds: ['top/bus#b[0]'],
      );
      api.responses['top/bus'] = [Data(time: 10, value: "4'b0000")];
      await repository.loadAndAppendWaveformData(
        signalIds: ['top/bus#b[0]'],
        startTime: 5,
        endTime: 10,
      );

      expect(
        repository.getWaveformById('top/bus#b[0]')!.data.map((d) => d.time),
        [0, 5, 10],
      );
    });

    test('returns an empty computed waveform when parent data is absent',
        () async {
      api.responses['top/bus'] = [];

      final synthesized = await repository.getWaveformData(
        signalIds: ['top/bus#b[0]'],
      );

      expect(synthesized.single.isComputed, isFalse);
      expect(synthesized.single.data, isEmpty);
    });

    test('synthesizes bit slices from hexadecimal, binary, and unknown values',
        () async {
      api.responses['top/bus'] = [
        Data(time: 0, value: '0x9'),
        Data(time: 1, value: '1010'),
        Data(time: 2, value: 'zzzz'),
        Data(time: 3, value: 'not-a-value'),
      ];

      final synthesized = await repository.getWaveformData(
        signalIds: ['top/bus#b[0]'],
      );

      expect(synthesized.single.data.map((d) => d.value), ['1', '0', 'x']);
    });

    test('synthesizes nested struct field waveform data', () async {
      bus.logicType = {
        'typeName': 'Packet',
        'fields': [
          {
            'name': 'payload',
            'width': 4,
            'bits': [0, 1, 2, 3],
            'type': {
              'typeName': 'Payload',
              'fields': [
                {
                  'name': 'lo',
                  'width': 2,
                  'bits': [0, 1],
                },
                {
                  'name': 'hi',
                  'width': 2,
                  'bits': [2, 3],
                },
              ],
            },
          },
        ],
      };

      final synthesized = await repository.getWaveformData(
        signalIds: ['top/bus#payload.hi'],
      );

      expect(synthesized.single.signalId, 'top/bus#payload.hi');
      expect(synthesized.single.isComputed, isTrue);
      expect(synthesized.single.data.map((d) => d.time), [0, 10]);
      expect(synthesized.single.data.map((d) => d.value), ["2'h2", "2'h0"]);
    });

    test('synthesizes array element waveform data', () async {
      bus.logicType = {
        'width': 4,
        'arrayDims': [2],
        'elementWidth': 2,
      };

      final synthesized = await repository.getWaveformData(
        signalIds: ['top/bus#[1]'],
      );

      expect(synthesized.single.signalId, 'top/bus#[1]');
      expect(synthesized.single.isComputed, isTrue);
      expect(synthesized.single.data.map((d) => d.time), [0, 10]);
      expect(synthesized.single.data.map((d) => d.value), ["2'h2", "2'h0"]);
    });
  });
}

class _FakeSignalWaveformApi extends SignalWaveformApi {
  _FakeSignalWaveformApi(this.responses);

  final Map<String, List<Data>> responses;
  final requests = <({List<String> signalIds, int? startTime, int? endTime})>[];
  final streamRequests = <({List<String> signalIds, int? startTime})>[];
  List<WaveformData> streamResponses = const [];
  bool isLoadedValue = true;
  int currentTime = 42;
  int currentTimeCalls = 0;
  int expandAllSlimModulesCalls = 0;

  @override
  bool get isLoaded => isLoadedValue;

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    requests.add((
      signalIds: List.of(signalIds),
      startTime: startTime,
      endTime: endTime,
    ));
    return [
      for (final signalId in signalIds)
        WaveformData(signalId: signalId, data: responses[signalId] ?? const []),
    ];
  }

  @override
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) async* {
    streamRequests.add((signalIds: List.of(signalIds), startTime: startTime));
    for (final response in streamResponses) {
      yield response;
    }
  }

  @override
  Future<int?> getCurrentTime() async {
    currentTimeCalls++;
    return currentTime;
  }

  @override
  Future<void> expandAllSlimModules() async {
    expandAllSlimModulesCalls++;
  }
}
