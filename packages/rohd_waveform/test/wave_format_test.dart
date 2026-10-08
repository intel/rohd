// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_format_test.dart
// Unit tests for the WaveFormat enumeration.
//
// 2026 July 15
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('WaveFormat', () {
    test('extension defaults to the enum name', () {
      for (final format in WaveFormat.values) {
        final expected = format == WaveFormat.unknown ? '' : '.${format.name}';
        expect(format.extension, expected);
      }
    });

    test('fromPath detects every format extension case-insensitively', () {
      for (final format in WaveFormat.values) {
        if (format.extension.isEmpty) {
          continue;
        }
        expect(
          WaveFormat.fromPath('sim/out${format.extension.toUpperCase()}'),
          format,
        );
      }
      expect(WaveFormat.fromPath('notes.txt'), WaveFormat.unknown);
    });

    test('fromString parses every enum name case-insensitively', () {
      for (final format in WaveFormat.values) {
        expect(WaveFormat.fromString(format.name.toUpperCase()), format);
      }
      expect(WaveFormat.fromString('mystery'), WaveFormat.unknown);
    });

    test('round-trips through name and fromString', () {
      for (final format in WaveFormat.values) {
        expect(WaveFormat.fromString(format.name), format);
      }
    });
  });
}
