// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_format_registry_test.dart
// Tests for shared signal display-format preferences and value formatting.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  test('formats bare binary and hexadecimal waveform values', () {
    expect(
      SignalValueFormatRegistry.formatValue('0000', 'waveform', 4),
      "4'h0",
    );
    expect(
      SignalValueFormatRegistry.formatValue('11111111', 'signedDecimal', 8),
      '-1',
    );
    expect(
      SignalValueFormatRegistry.formatValue('11111111', 'hexadecimal', 8),
      "8'hff",
    );
    expect(
      SignalValueFormatRegistry.formatValue('ff', 'unsignedDecimal', 8),
      '255',
    );
    expect(
      SignalValueFormatRegistry.formatValue('0x0', 'unsignedDecimal', 4),
      '0',
    );
  });

  test('looks up equivalent dotted and slash-separated paths', () {
    SignalValueFormatRegistry.update({'top/adder/result': 'signedDecimal'});

    expect(
      SignalValueFormatRegistry.formatFor('top.adder.result'),
      'signedDecimal',
    );
  });

  test('looks up a fallback waveform identity', () {
    SignalValueFormatRegistry.update({'top/adder/result': 'unsignedDecimal'});

    expect(
      SignalValueFormatRegistry.formatForAny([
        'unresolved-id',
        'top/adder/result',
      ]),
      'unsignedDecimal',
    );
  });

  test('looks up a uniquely matching hierarchy suffix', () {
    SignalValueFormatRegistry.update({
      'waveform-root/top/adder/result': 'unsignedDecimal',
    });

    expect(
      SignalValueFormatRegistry.formatFor('schematic-root/top/adder/result'),
      'unsignedDecimal',
    );
  });

  test('does not use an ambiguous hierarchy suffix', () {
    SignalValueFormatRegistry.update({
      'top/left/result': 'unsignedDecimal',
      'top/right/result': 'signedDecimal',
    });

    expect(SignalValueFormatRegistry.formatFor('result'), 'waveform');
  });
}
