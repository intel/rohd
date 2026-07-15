// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_format_test.dart
// Unit tests for the WaveFormat enumeration.
//
// 2026

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('WaveFormat', () {
    test('extension returns the expected file suffix', () {
      expect(WaveFormat.vcd.extension, '.vcd');
      expect(WaveFormat.fst.extension, '.fst');
      expect(WaveFormat.ghw.extension, '.ghw');
      expect(WaveFormat.unknown.extension, '');
    });

    test('fromPath detects format from a file path', () {
      expect(WaveFormat.fromPath('sim/out.VCD'), WaveFormat.vcd);
      expect(WaveFormat.fromPath('/tmp/dump.fst'), WaveFormat.fst);
      expect(WaveFormat.fromPath('design.ghw'), WaveFormat.ghw);
      expect(WaveFormat.fromPath('notes.txt'), WaveFormat.unknown);
    });

    test('fromString parses a format name case-insensitively', () {
      expect(WaveFormat.fromString('VCD'), WaveFormat.vcd);
      expect(WaveFormat.fromString('fst'), WaveFormat.fst);
      expect(WaveFormat.fromString('Ghw'), WaveFormat.ghw);
      expect(WaveFormat.fromString('mystery'), WaveFormat.unknown);
    });

    test('round-trips through name and fromString', () {
      for (final format in WaveFormat.values) {
        if (format == WaveFormat.unknown) {
          continue;
        }
        expect(WaveFormat.fromString(format.name), format);
      }
    });

    test('supportsWriting matches the documented formats', () {
      expect(WaveFormat.vcd.supportsWriting, isTrue);
      expect(WaveFormat.fst.supportsWriting, isTrue);
      expect(WaveFormat.ghw.supportsWriting, isFalse);
      expect(WaveFormat.unknown.supportsWriting, isFalse);
    });

    test('supportsReading matches the documented formats', () {
      expect(WaveFormat.vcd.supportsReading, isTrue);
      expect(WaveFormat.fst.supportsReading, isTrue);
      expect(WaveFormat.ghw.supportsReading, isTrue);
      expect(WaveFormat.unknown.supportsReading, isFalse);
    });
  });
}
