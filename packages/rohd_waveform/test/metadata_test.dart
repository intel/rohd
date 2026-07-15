// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// metadata_test.dart
// Unit tests for the MetaData and Data models.
//
// 2026

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('Data', () {
    test('round-trips through JSON', () {
      final data = Data(time: 42, value: '1010');
      final restored = Data.fromJson(data.toJson());
      expect(restored.time, 42);
      expect(restored.value, '1010');
    });

    test('empty starts at time zero with value 0', () {
      final data = Data.empty();
      expect(data.time, 0);
      expect(data.value, '0');
    });
  });

  group('MetaData', () {
    test('value equality via Equatable', () {
      const a = MetaData(source: 'a.vcd', timescale: '1ns', date: 'today');
      const b = MetaData(source: 'a.vcd', timescale: '1ns', date: 'today');
      const c = MetaData(source: 'b.vcd', timescale: '1ns', date: 'today');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('empty has blank fields and zero range', () {
      final meta = MetaData.empty();
      expect(meta.source, isEmpty);
      expect(meta.timescale, isEmpty);
      expect(meta.date, isEmpty);
      expect(meta.startTime, 0);
      expect(meta.endTime, 0);
      expect(meta.format, isNull);
    });

    test('round-trips full payload through JSON', () {
      const meta = MetaData(
        source: 'dump.fst',
        timescale: '100ps',
        date: '2026-01-01',
        startTime: 5,
        endTime: 500,
        timescaleFactor: 100,
        version: 'sim-1.2',
        format: WaveFormat.fst,
      );
      final restored = MetaData.fromJson(meta.toJson());
      expect(restored, equals(meta));
      expect(restored.format, WaveFormat.fst);
      expect(restored.timescaleFactor, 100);
      expect(restored.version, 'sim-1.2');
    });

    test('omits optional fields from JSON when null', () {
      const meta = MetaData(source: 's', timescale: 't', date: 'd');
      final json = meta.toJson();
      expect(json.containsKey('timescaleFactor'), isFalse);
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('format'), isFalse);
    });
  });
}
