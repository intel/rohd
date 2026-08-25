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
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  test('formats bare binary and hexadecimal waveform values', () {
    expect(
      SignalValueFormatRegistry.formatValue(
        '0000',
        SignalValueFormat.waveform,
        4,
      ),
      "4'h0",
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        '11111111',
        SignalValueFormat.signedDecimal,
        8,
      ),
      '-1',
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        '11111111',
        SignalValueFormat.hexadecimal,
        8,
      ),
      "8'hff",
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        'ff',
        SignalValueFormat.unsignedDecimal,
        8,
      ),
      '255',
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        '0x0',
        SignalValueFormat.unsignedDecimal,
        4,
      ),
      '0',
    );
  });

  test('uses ROHD radix literals for typed format conversions', () {
    expect(
      SignalValueFormatRegistry.formatValue(
        "8'd255",
        SignalValueFormat.hexadecimal,
        8,
      ),
      "8'hff",
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        '1010',
        SignalValueFormat.octal,
        4,
      ),
      '0o12',
    );
    expect(
      SignalValueFormatRegistry.formatValue(
        '0x4142',
        SignalValueFormat.ascii,
        16,
      ),
      'AB',
    );
  });

  test('looks up an occurrence address from the format trie', () {
    SignalValueFormatRegistry.setFormatFor(
      [
        const OccurrenceAddress([0, 2, 4]),
      ],
      SignalValueFormat.signedDecimal,
    );

    expect(
      SignalValueFormatRegistry.formatFor(const OccurrenceAddress([0, 2, 4])),
      SignalValueFormat.signedDecimal,
    );
  });

  test('looks up a fallback occurrence address', () {
    SignalValueFormatRegistry.setFormatFor(
      [
        const OccurrenceAddress([0, 2, 4]),
      ],
      SignalValueFormat.unsignedDecimal,
    );

    expect(
      SignalValueFormatRegistry.formatForAny([
        const OccurrenceAddress([7, 8, 9]),
        const OccurrenceAddress([0, 2, 4]),
      ]),
      SignalValueFormat.unsignedDecimal,
    );
  });

  test('stores shared address prefixes once in the format trie', () {
    SignalValueFormatRegistry.update([
      SignalValueFormatPreference(
        const OccurrenceAddress([0, 2, 4]),
        SignalValueFormat.unsignedDecimal,
      ),
      SignalValueFormatPreference(
        const OccurrenceAddress([0, 2, 5]),
        SignalValueFormat.signedDecimal,
      ),
    ]);

    expect(
      SignalValueFormatRegistry.formatFor(const OccurrenceAddress([0, 2, 4])),
      SignalValueFormat.unsignedDecimal,
    );
    expect(
      SignalValueFormatRegistry.formatFor(const OccurrenceAddress([0, 2, 5])),
      SignalValueFormat.signedDecimal,
    );
    expect(
      SignalValueFormatRegistry.formatFor(const OccurrenceAddress([0, 2, 6])),
      SignalValueFormat.waveform,
    );
  });

  test('rejects an invalid signal occurrence address', () {
    expect(
      () => SignalValueFormatRegistry.setFormatFor(
        const [OccurrenceAddress([])],
        SignalValueFormat.unsignedDecimal,
      ),
      throwsArgumentError,
    );
    expect(
      () => SignalValueFormatRegistry.formatFor(
        const OccurrenceAddress([0, -1]),
      ),
      throwsArgumentError,
    );
  });

  test('converts between serialized names and format enum values', () {
    expect(
      SignalValueFormatRegistry.formatFromString('signedDecimal'),
      SignalValueFormat.signedDecimal,
    );
    expect(
      SignalValueFormatRegistry.formatToString(
        SignalValueFormat.signedDecimal,
      ),
      'signedDecimal',
    );
    expect(SignalValueFormatRegistry.formatFromString('unknown'), isNull);
  });
}
