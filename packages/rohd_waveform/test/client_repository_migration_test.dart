// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// client_repository_migration_test.dart
// Regression tests promoted from the ROHD Wave Viewer client repository.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

class _TestWaveformApi extends SignalWaveformApi {
  final String signalId;

  const _TestWaveformApi(this.signalId);

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async =>
      signalIds.contains(signalId)
          ? [
              WaveformData(
                signalId: signalId,
                data: [
                  Data(time: 0, value: "17'h00001"),
                  Data(time: 10, value: "17'h08000"),
                  Data(time: 20, value: "17'h10001"),
                ],
              ),
            ]
          : const [];
}

class _RecordingWaveformApi extends SignalWaveformApi {
  final Map<String, List<Data>> waveformData;
  final List<WaveformData> streamedData;
  final int? currentTime;
  final List<({List<String> signalIds, int? startTime, int? endTime})>
      requests = <({List<String> signalIds, int? startTime, int? endTime})>[];
  bool didExpandSlimModules = false;
  bool loaded = true;

  _RecordingWaveformApi({
    required this.waveformData,
    this.streamedData = const [],
    this.currentTime,
  });

  @override
  Future<void> expandAllSlimModules() async {
    didExpandSlimModules = true;
  }

  @override
  bool get isLoaded => loaded;

  @override
  Future<int?> getCurrentTime() async => currentTime;

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
        if (waveformData[signalId] case final data?)
          WaveformData(
            signalId: signalId,
            data: [
              for (final point in data)
                if ((startTime == null || point.time >= startTime) &&
                    (endTime == null || point.time <= endTime))
                  point,
            ],
          ),
    ];
  }

  @override
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) =>
      Stream.fromIterable([
        for (final waveform in streamedData)
          if (signalIds.contains(waveform.signalId))
            WaveformData(
              signalId: waveform.signalId,
              data: [
                for (final point in waveform.data)
                  if (startTime == null || point.time >= startTime) point,
              ],
            ),
      ]);
}

HierarchyOccurrence _hierarchy() => HierarchyOccurrence(
      name: 'top',
      signals: [
        SignalOccurrence(name: 'clock', width: 1),
        SignalOccurrence(name: 'data', width: 8),
      ],
      children: [
        HierarchyOccurrence(
          name: 'child',
          signals: [SignalOccurrence(name: 'valid', width: 1)],
        ),
      ],
    );

void main() {
  group('SignalWaveformRepository', () {
    test('builds recursive signal caches and manages selected waveforms', () {
      final root = _hierarchy()..buildAddresses();
      final clock = root.signals.first;
      final childValid = root.children.single.signals.single;
      final repository = SignalWaveformRepository(
        signalWaveformApi: _RecordingWaveformApi(waveformData: {}),
      )..buildSignalCacheFromHierarchy([root]);

      expect(
        repository.cachedSignalIds,
        containsAll([clock.path(), childValid.path()]),
      );
      expect(repository.getSignal(clock.address!), same(clock));
      expect(repository.getSignalById(childValid.path()), same(childValid));

      final waveforms = repository.getWaveformsBySelectedModule(root);
      expect(waveforms.map((waveform) => waveform.signalId), [
        clock.path(),
        root.signals[1].path(),
      ]);
      expect(repository.clearWaveformData(clock.address!), isTrue);
      expect(repository.clearWaveformData(childValid.address!), isTrue);

      repository.clearAllWaveformData();
      expect(repository.getWaveform(clock.address!), isNull);
      expect(repository.getSignal(clock.address!), same(clock));
      repository.clearSignalCache();
      expect(repository.cachedSignalAddresses, isEmpty);
    });

    test(
      'replaces complete fetches and appends sorted ranged fetches',
      () async {
        final root = _hierarchy()..buildAddresses();
        final signal = root.signals[1];
        final api = _RecordingWaveformApi(
          waveformData: {
            signal.path(): [
              Data(time: 20, value: '14'),
              Data(time: 0, value: '0'),
              Data(time: 10, value: 'a'),
            ],
          },
        );
        final repository = SignalWaveformRepository(signalWaveformApi: api)
          ..buildSignalCacheFromHierarchy([root]);

        await repository.loadAndAppendWaveformData(signalIds: [signal.path()]);
        api.waveformData[signal.path()]!.add(Data(time: 30, value: '1e'));
        await repository.loadAndAppendWaveformData(
          signalIds: [signal.path()],
          startTime: 25,
          endTime: 30,
        );

        expect(
          repository
              .getWaveformById(signal.path())!
              .data
              .map((point) => point.time),
          [0, 10, 20, 30],
        );
        expect(api.requests.last.signalIds, [signal.path()]);
        expect(api.requests.last.startTime, 25);
        expect(api.requests.last.endTime, 30);

        await repository.loadAndAppendWaveformData(signalIds: [signal.path()]);
        expect(
          repository
              .getWaveformById(signal.path())!
              .data
              .map((point) => point.time),
          [20, 0, 10, 30],
        );
      },
    );

    test('streams into signal and computed waveform caches', () async {
      final root = _hierarchy()..buildAddresses();
      final signal = root.signals[1];
      final computedId = '${signal.path()}#display';
      final repository = SignalWaveformRepository(
        signalWaveformApi: _RecordingWaveformApi(
          waveformData: {},
          streamedData: [
            WaveformData(
              signalId: signal.path(),
              data: [Data(time: 0, value: '0')],
            ),
            WaveformData(
              signalId: computedId,
              data: [Data(time: 5, value: 'shown')],
            ),
          ],
        ),
      )..buildSignalCacheFromHierarchy([root]);

      final streamed = await repository
          .streamWaveformData(signalIds: [signal.path(), computedId]).toList();

      expect(streamed, hasLength(2));
      expect(repository.getWaveformById(signal.path())!.data.single.value, '0');
      expect(
        repository.getWaveformById(computedId)!.data.single.value,
        'shown',
      );

      final noAppendRepository = SignalWaveformRepository(
        signalWaveformApi: _RecordingWaveformApi(
          waveformData: {},
          streamedData: [
            WaveformData(
              signalId: signal.path(),
              data: [Data(time: 10, value: '1')],
            ),
          ],
        ),
      )..buildSignalCacheFromHierarchy([root]);
      await noAppendRepository.streamWaveformData(
        signalIds: [signal.path()],
        appendToSignals: false,
      ).drain<void>();
      expect(noAppendRepository.getWaveformById(signal.path())!.data, isEmpty);
    });

    test('waits for a loading API before retrieving data', () async {
      final api = _RecordingWaveformApi(waveformData: {}, currentTime: 7)
        ..loaded = false;
      final repository = SignalWaveformRepository(
        signalWaveformApi: api,
        apiReady: Completer<void>().future,
      );

      Future<void>.delayed(
        const Duration(milliseconds: 1),
        () => api.loaded = true,
      );

      expect(await repository.getCurrentTime(), 7);
    });

    test(
      'resolves array fields and propagates API lifecycle operations',
      () async {
        final arraySignal = SignalOccurrence(
          name: 'lanes',
          width: 8,
          logicType: {
            'arrayDims': [2],
            'elementWidth': 4,
          },
        );
        final root = HierarchyOccurrence(name: 'top', signals: [arraySignal])
          ..buildAddresses();
        final firstApi = _RecordingWaveformApi(
          waveformData: {
            arraySignal.path(): [Data(time: 0, value: "8'hb0")],
          },
          currentTime: 42,
        );
        final repository = SignalWaveformRepository(signalWaveformApi: firstApi)
          ..buildSignalCacheFromHierarchy([root]);
        final sliceId = '${arraySignal.path()}#[1]#b[2:1]';

        final waveformData = await repository.getWaveformData(
          signalIds: [sliceId, '${arraySignal.path()}#b[8]'],
        );
        expect(waveformData.single.data.single.value, "2'h1");
        expect(await repository.getCurrentTime(), 42);
        await repository.expandAllSlimModules();
        expect(firstApi.didExpandSlimModules, isTrue);

        repository.appendDataToSignal(sliceId, [Data(time: 1, value: "2'h3")]);
        expect(repository.getWaveformById(sliceId), isNotNull);
        repository.setSignalWaveformApi(
          _RecordingWaveformApi(waveformData: {}),
        );
        expect(repository.cachedSignalAddresses, isEmpty);
        expect(repository.getWaveformById(sliceId), isNull);
      },
    );

    test('ignores invalid sub-fields and caches empty valid slices', () async {
      final signal = SignalOccurrence(name: 'data', width: 4);
      final root = HierarchyOccurrence(name: 'top', signals: [signal])
        ..buildAddresses();
      final repository = SignalWaveformRepository(
        signalWaveformApi: _RecordingWaveformApi(
          waveformData: {signal.path(): const []},
        ),
      )..buildSignalCacheFromHierarchy([root]);

      final result = await repository.getWaveformData(
        signalIds: [
          '${signal.path()}#field',
          '${signal.path()}#b[4]',
          '${signal.path()}#b[0]',
          '#b[0]',
        ],
      );

      expect(result, hasLength(1));
      expect(result.single.signalId, '${signal.path()}#b[0]');
      expect(result.single.data, isEmpty);
    });

    test(
      'preserves positioned X/Z bits without contaminating known slices',
      () async {
        final signal = SignalOccurrence(name: 'state', width: 8);
        final root = HierarchyOccurrence(name: 'top', signals: [signal])
          ..buildAddresses();
        final repository = SignalWaveformRepository(
          signalWaveformApi: _RecordingWaveformApi(
            waveformData: {
              signal.path(): [
                Data(time: 0, value: "8'b10xz0110"),
                Data(time: 10, value: "8'hf"),
              ],
            },
          ),
        )..buildSignalCacheFromHierarchy([root]);
        final upperKnownId = '${signal.path()}#b[7:6]';
        final lowerKnownId = '${signal.path()}#b[3:0]';
        final mixedId = '${signal.path()}#b[5:2]';
        final zBitId = '${signal.path()}#b[4]';

        final waveforms = await repository.getWaveformData(
          signalIds: [upperKnownId, lowerKnownId, mixedId, zBitId],
        );
        final valuesById = {
          for (final waveform in waveforms)
            waveform.signalId:
                waveform.data.map((point) => point.value).toList(),
        };

        expect(valuesById[upperKnownId], ["2'h2", "2'h0"]);
        expect(valuesById[lowerKnownId], ["4'h6", "4'hf"]);
        expect(valuesById[mixedId], ["4'bxz01", "4'h3"]);
        expect(valuesById[zBitId], ['z', '0']);
      },
    );

    test(
      'synthesizes bits from an already-synthesized structure field',
      () async {
        final sample = SignalOccurrence(
          name: 'sample',
          width: 17,
          logicType: {
            'typeName': 'FilterSample',
            'fields': [
              {
                'name': 'data',
                'width': 16,
                'bits': List<int>.generate(16, (index) => index),
              },
              {
                'name': 'valid',
                'width': 1,
                'bits': [16],
              },
            ],
          },
        );
        final root = HierarchyOccurrence(name: 'FilterBank', signals: [sample])
          ..buildAddresses();

        final repository = SignalWaveformRepository(
          signalWaveformApi: _TestWaveformApi(sample.path()),
        )..buildSignalCacheFromHierarchy([root]);
        final fieldId = '${sample.path()}#data';
        final bitZeroId = '$fieldId#b[0]';
        final bitFifteenId = '$fieldId#b[15]';

        await repository.loadAndAppendWaveformData(signalIds: [fieldId]);
        await repository.loadAndAppendWaveformData(
          signalIds: [bitZeroId, bitFifteenId],
        );

        expect(
          repository.getWaveformById(fieldId)!.data.map((point) => point.value),
          ["16'h0001", "16'h8000", "16'h0001"],
        );
        expect(
          repository
              .getWaveformById(bitZeroId)!
              .data
              .map((point) => point.value),
          ['1', '0', '1'],
        );
        expect(
          repository
              .getWaveformById(bitFifteenId)!
              .data
              .map((point) => point.value),
          ['0', '1', '0'],
        );
      },
    );
  });
}
