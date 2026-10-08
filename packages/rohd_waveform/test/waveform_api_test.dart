// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_api_test.dart
// Unit tests for default SignalWaveformApi behavior.
//
// 2026 July 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('SignalWaveformApi defaults', () {
    test('base implementation reports itself loaded', () {
      expect(const _BaseOnlySignalWaveformApi().isLoaded, isTrue);
    });

    test('base methods throw when subclasses do not implement them', () async {
      const api = _BaseOnlySignalWaveformApi();

      await expectLater(
        api.getWaveformData(signalIds: ['top/clk']),
        throwsA(isA<UnimplementedError>()),
      );
      await expectLater(
          api.getCurrentTime(), throwsA(isA<UnimplementedError>()));
      await expectLater(
          api.getSnapshot(10), throwsA(isA<UnimplementedError>()));
    });

    test('default streamWaveformData yields getWaveformData results', () async {
      final api = _StreamingSignalWaveformApi([
        WaveformData(
          signalId: 'top/clk',
          data: [Data(time: 0, value: '0')],
        ),
        WaveformData(
          signalId: 'top/rst',
          data: [Data(time: 0, value: '1')],
        ),
      ]);

      final streamed = await api.streamWaveformData(
          signalIds: ['top/clk', 'top/rst'], startTime: 5).toList();

      expect(streamed.map((w) => w.signalId), ['top/clk', 'top/rst']);
      expect(api.requestedSignalIds, ['top/clk', 'top/rst']);
      expect(api.requestedStartTime, 5);
    });

    test('default expandAllSlimModules is a no-op', () async {
      await expectLater(
        const _BaseOnlySignalWaveformApi().expandAllSlimModules(),
        completes,
      );
    });
  });
}

class _BaseOnlySignalWaveformApi extends SignalWaveformApi {
  const _BaseOnlySignalWaveformApi();
}

class _StreamingSignalWaveformApi extends SignalWaveformApi {
  _StreamingSignalWaveformApi(this.response);

  final List<WaveformData> response;
  List<String> requestedSignalIds = const [];
  int? requestedStartTime;

  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    requestedSignalIds = List.of(signalIds);
    requestedStartTime = startTime;
    return response;
  }
}
