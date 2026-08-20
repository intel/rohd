// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_structure_layout_test.dart
// Tests for packed LogicStructure layout synthesis utilities.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

void main() {
  group('SynthStructureLayout', () {
    test('uses least-significant-first element offsets', () {
      final structure = LogicStructure([
        Logic(name: 'low', width: 2),
        Logic(name: 'high', width: 3),
      ]);
      final layout = SynthStructureLayout(structure);

      expect(layout.fieldNameAt(0, fallbackName: 'fallback'), 'low');
      expect(layout.fieldNameAt(1, fallbackName: 'fallback'), 'low');
      expect(layout.fieldNameAt(2, fallbackName: 'fallback'), 'high');
      expect(layout.fieldNameAt(4, fallbackName: 'fallback'), 'high');
      expect(layout.fieldNameAt(5, fallbackName: 'fallback'), 'fallback');
    });

    test('qualifies an unpreferred nested leaf by parent and index', () {
      final nested = LogicStructure([
        Logic(name: Naming.unpreferredName('first'), width: 2),
        Logic(name: Naming.unpreferredName('second'), width: 2),
      ], name: 'payload');
      final structure = LogicStructure([
        Logic(name: 'header'),
        nested,
      ]);
      final layout = SynthStructureLayout(structure);

      expect(layout.fieldNameAt(1, fallbackName: 'fallback'), 'payload_0');
      expect(layout.fieldNameAt(3, fallbackName: 'fallback'), 'payload_1');
    });

    test('returns bit ranges for nested field paths', () {
      final nested = LogicStructure([
        Logic(name: 'b', width: 2),
        LogicStructure([
          Logic(name: 'd', width: 3),
        ], name: 'c'),
      ], name: 'a');
      final structure = LogicStructure([
        Logic(name: 'prefix'),
        nested,
      ]);
      final layout = SynthStructureLayout(structure);

      expect(layout.bitRangeForPath('a'), (start: 1, end: 6));
      expect(layout.bitRangeForPath('a.b'), (start: 1, end: 3));
      expect(layout.bitRangeForPath('a.c'), (start: 3, end: 6));
      expect(layout.bitRangeForPath('a.c.d'), (start: 3, end: 6));
      expect(layout.bitRangeForPath('a.missing'), isNull);
    });

    test('supports unpack-specific anonymous field names', () {
      final fieldName = Naming.unpreferredName('field');
      final structure = LogicStructure([Logic(name: fieldName)]);
      final layout = SynthStructureLayout(structure);

      expect(layout.fieldNameAt(0, fallbackName: 'fallback'), fieldName);
      expect(
        layout.fieldNameAt(
          0,
          fallbackName: 'fallback',
          anonymousUnpreferred: true,
        ),
        'anonymous_0',
      );
    });

    test('does not recurse into LogicArray elements', () {
      final structure = LogicStructure([
        LogicArray([2], 3, name: 'entries'),
        Logic(name: 'tail'),
      ]);
      final layout = SynthStructureLayout(structure);

      expect(layout.fieldNameAt(0, fallbackName: 'fallback'), 'entries');
      expect(layout.fieldNameAt(5, fallbackName: 'fallback'), 'entries');
      expect(layout.fieldNameAt(6, fallbackName: 'fallback'), 'tail');
    });
  });
}
