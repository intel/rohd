// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_waveform_test.dart
// Unit tests for SignalWaveform and WaveformData (no signal lookup required).
//
// 2026 July 15
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  // Ensure a clean static lookup state for these pure-data tests.
  setUp(SignalWaveform.clearSignalLookup);
  tearDown(SignalWaveform.clearSignalLookup);

  group('SignalWaveform metadata fallbacks (no lookup)', () {
    test('name and width fall back to signalId metadata', () {
      final wf = SignalWaveform(signalId: 'clk');
      expect(wf.signal, isNull);
      expect(wf.name, 'clk');
      expect(wf.width, 1);
      expect(wf.hierarchyPath, 'clk');
      expect(wf.id, 'clk');
      expect(wf.isPort, isFalse);
      expect(wf.isSubField, isFalse);
    });

    test('derives bit-slice name and width from signalId', () {
      final waveform = SignalWaveform(signalId: 'top/value#b[15:8]');

      expect(waveform.isSubField, isTrue);
      expect(waveform.name, 'value[15:8]');
      expect(waveform.width, 8);
    });

    test('derives structural field metadata from its parent signal', () {
      final parent = SignalOccurrence(
        name: 'value',
        width: 16,
        logicType: {
          'fields': [
            {
              'name': 'exponent',
              'width': 5,
              'bits': [8, 9, 10, 11, 12],
            },
          ],
        },
      );
      SignalWaveform.signalLookup = (id) => id == 'top/value' ? parent : null;
      final waveform = SignalWaveform(signalId: 'top/value#exponent');

      expect(waveform.name, 'value_exponent');
      expect(waveform.width, 5);
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

    test('computed state is set when constructing or copying a waveform', () {
      final computed = SignalWaveform.empty('s', isComputed: true);
      final preserved = SignalWaveform.copyFrom(computed);
      final overridden = SignalWaveform.copyFrom(computed, isComputed: false);

      expect(computed.isComputed, isTrue);
      expect(preserved.isComputed, isTrue);
      expect(overridden.isComputed, isFalse);
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
    final wf = SignalWaveform(
      signalId: 's',
      data: [
        Data(time: 0, value: '0'),
        Data(time: 10, value: '1'),
        Data(time: 20, value: '0'),
      ],
    );

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
    final wf = SignalWaveform(
      signalId: 's',
      data: [
        Data(time: 0, value: '0'),
        Data(time: 10, value: '1'),
        Data(time: 10, value: '1'),
        Data(time: 20, value: '0'),
      ],
    );

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

  group('SignalWaveform matching navigation', () {
    final wf = SignalWaveform(
      signalId: 's',
      data: [
        Data(time: 0, value: '0'),
        Data(time: 10, value: '1'),
        Data(time: 20, value: '0'),
        Data(time: 30, value: "1'b1"),
      ],
    );

    test('finds values and edges in both directions', () {
      expect(
        wf.getNextMatchingDataPointIndex(
          0,
          criterion: WaveformSearchCriterion.risingEdge,
        ),
        1,
      );
      expect(
        wf.getNextMatchingDataPointIndex(
          10,
          criterion: WaveformSearchCriterion.fallingEdge,
        ),
        2,
      );
      expect(
        wf.getPreviousMatchingDataPointIndex(
          31,
          criterion: WaveformSearchCriterion.value,
          value: '0',
        ),
        2,
      );
    });
  });

  group('SignalWaveform copy/serialization', () {
    test('copyFrom produces an independent data list', () {
      final original = SignalWaveform(
        signalId: 's',
        data: [Data(time: 0, value: '0')],
        monitorGroup: 'inputs',
        valueFormat: MonitorValueFormat.hexadecimal,
      );
      final copy = SignalWaveform.copyFrom(original);
      expect(copy.signalId, 's');
      expect(copy.monitorId, isNot(original.monitorId));
      expect(copy.monitorGroup, 'inputs');
      expect(copy.valueFormat, MonitorValueFormat.hexadecimal);

      copy.appendData([Data(time: 5, value: '1')]);
      expect(original.length, 1, reason: 'copy must not mutate the original');
      expect(copy.length, 2);
    });

    test('supports explicit monitor identity and display name', () {
      final original = SignalWaveform(signalId: 's');
      final copy = SignalWaveform.copyFrom(original, monitorId: 's-copy');
      final monitored = MonitoredSignal.fromWaveform(
        copy,
        displayName: 'Status',
      );

      expect(copy.monitorId, 's-copy');
      expect(monitored.monitorId, 's-copy');
      expect(monitored.name, 'Status');
    });

    test('round-trips through JSON', () {
      final wf = SignalWaveform(
        signalId: 'sig',
        data: [
          Data(time: 0, value: '0'),
          Data(time: 4, value: '1'),
        ],
      );
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
      final wd = WaveformData(
        signalId: 's',
        data: [
          Data(time: 3, value: '0'),
          Data(time: 9, value: '1'),
        ],
      );
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
      final wf = SignalWaveform.fromWaveformData(wd, signalId: 'top/s');
      expect(wf.signalId, 'top/s');
      expect(wf.length, 1);
      expect(wf.isComputed, isTrue);
    });
  });
}
