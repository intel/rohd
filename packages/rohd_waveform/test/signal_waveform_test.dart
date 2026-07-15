// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_waveform_test.dart
// Unit tests for SignalWaveform and WaveformData (no signal lookup required).
//
// 2026

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  // Ensure a clean static lookup state for these pure-data tests.
  setUp(SignalWaveform.clearSignalLookup);
  tearDown(SignalWaveform.clearSignalLookup);

  group('SignalWaveform metadata fallbacks (no lookup)', () {
    test('name/width fall back to overrides then signalId', () {
      final wf = SignalWaveform(signalId: 'clk');
      expect(wf.signal, isNull);
      expect(wf.name, 'clk');
      expect(wf.width, 1);
      expect(wf.hierarchyPath, 'clk');
      expect(wf.id, 'clk');
      expect(wf.isPort, isFalse);

      final overridden = SignalWaveform(
        signalId: 'sig0',
        overrideName: 'bus',
        overrideWidth: 8,
      );
      expect(overridden.name, 'bus');
      expect(overridden.width, 8);
    });

    test('empty and length reflect data', () {
      final wf = SignalWaveform.empty('s');
      expect(wf.isEmpty, isTrue);
      expect(wf.isNotEmpty, isFalse);
      expect(wf.length, 0);

      wf.appendData([Data(time: 0, value: '0')]);
      expect(wf.isEmpty, isFalse);
      expect(wf.length, 1);

      wf.clearData();
      expect(wf.isEmpty, isTrue);
    });
  });

  group('SignalWaveform.appendData', () {
    test('sortByTime sorts and dedups keeping the latest value', () {
      final wf = SignalWaveform(signalId: 's')
        ..appendData([
          Data(time: 10, value: 'a'),
          Data(time: 0, value: 'x'),
          Data(time: 10, value: 'b'),
        ], sortByTime: true);

      expect(wf.data.map((d) => d.time).toList(), [0, 10]);
      // Last value at duplicate timestamp 10 wins.
      expect(wf.getValueByTime(10), 'b');
      expect(wf.getValueByTime(0), 'x');
    });
  });

  group('SignalWaveform.getValueByTime (binary search)', () {
    final wf = SignalWaveform(signalId: 's', data: [
      Data(time: 0, value: '0'),
      Data(time: 10, value: '1'),
      Data(time: 20, value: '0'),
    ]);

    test('returns the value at or before a time', () {
      expect(wf.getValueByTime(0), '0');
      expect(wf.getValueByTime(5), '0');
      expect(wf.getValueByTime(10), '1');
      expect(wf.getValueByTime(15), '1');
      expect(wf.getValueByTime(100), '0');
    });

    test('returns first value before the first sample', () {
      expect(wf.getValueByTime(-5), '0');
    });

    test('empty waveform returns empty string', () {
      expect(SignalWaveform.empty('e').getValueByTime(3), '');
    });
  });

  group('SignalWaveform navigation indices', () {
    final wf = SignalWaveform(signalId: 's', data: [
      Data(time: 0, value: '0'),
      Data(time: 10, value: '1'),
      Data(time: 10, value: '1'),
      Data(time: 20, value: '0'),
    ]);

    test('getNextDataPointIndex skips duplicates at current time', () {
      expect(wf.getNextDataPointIndex(0), 1);
      expect(wf.getNextDataPointIndex(10), 3);
      expect(wf.getNextDataPointIndex(20), -1);
    });

    test('getPreviousDataPointIndex skips duplicates at current time', () {
      expect(wf.getPreviousDataPointIndex(20), 2);
      expect(wf.getPreviousDataPointIndex(10), 0);
      expect(wf.getPreviousDataPointIndex(0), -1);
    });
  });

  group('SignalWaveform copy/serialization', () {
    test('copyFrom produces an independent data list', () {
      final original = SignalWaveform(
        signalId: 's',
        data: [Data(time: 0, value: '0')],
        overrideName: 'n',
        overrideWidth: 4,
      );
      final copy = SignalWaveform.copyFrom(original);
      expect(copy.signalId, 's');
      expect(copy.overrideName, 'n');
      expect(copy.overrideWidth, 4);

      copy.appendData([Data(time: 5, value: '1')]);
      expect(original.length, 1, reason: 'copy must not mutate the original');
      expect(copy.length, 2);
    });

    test('round-trips through JSON', () {
      final wf = SignalWaveform(signalId: 'sig', data: [
        Data(time: 0, value: '0'),
        Data(time: 4, value: '1'),
      ]);
      final restored = SignalWaveform.fromJson(wf.toJson());
      expect(restored.signalId, 'sig');
      expect(restored.length, 2);
      expect(restored.getValueByTime(4), '1');
    });
  });

  group('WaveformData', () {
    test('empty payload reports no data and null bounds', () {
      final wd = WaveformData.empty('s');
      expect(wd.isEmpty, isTrue);
      expect(wd.length, 0);
      expect(wd.startTime, isNull);
      expect(wd.endTime, isNull);
    });

    test('reports start/end times from its samples', () {
      final wd = WaveformData(signalId: 's', data: [
        Data(time: 3, value: '0'),
        Data(time: 9, value: '1'),
      ]);
      expect(wd.startTime, 3);
      expect(wd.endTime, 9);
      expect(wd.isNotEmpty, isTrue);
    });

    test('round-trips through JSON', () {
      final wd = WaveformData(
        signalId: 's',
        data: [Data(time: 1, value: '1')],
        isComputed: true,
      );
      final restored = WaveformData.fromJson(wd.toJson());
      expect(restored.signalId, 's');
      expect(restored.length, 1);
    });

    test('SignalWaveform.fromWaveformData copies data and flags', () {
      final wd = WaveformData(
        signalId: 's',
        data: [Data(time: 0, value: '0')],
        isComputed: true,
      );
      final wf = SignalWaveform.fromWaveformData(wd);
      expect(wf.signalId, 's');
      expect(wf.length, 1);
      expect(wf.isComputed, isTrue);
    });
  });
}
