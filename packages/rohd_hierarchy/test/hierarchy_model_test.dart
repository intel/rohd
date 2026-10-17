// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_model_test.dart
// Cross-platform hierarchy model and utility tests.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

void main() {
  group('HierarchyOccurrence legacy ports', () {
    test('returns independent mutable snapshots of the current signals', () {
      final first =
          SignalOccurrence(name: 'first', width: 1, direction: 'input');
      final second =
          SignalOccurrence(name: 'second', width: 1, direction: 'output');
      final signals = [first];
      final occurrence = HierarchyOccurrence(name: 'root', signals: signals)
        ..ports.clear();
      expect(occurrence.ports, [first]);
      expect(occurrence.portByName('first'), same(first));

      signals.add(second);
      expect(occurrence.ports, [first, second]);
      expect(occurrence.portCount, 2);
      expect(occurrence.portByName('second'), same(second));

      signals.remove(first);
      expect(occurrence.ports, [second]);
      expect(occurrence.portByName('first'), isNull);
    });
  });

  group('HierarchyOccurrence primitive detection', () {
    test(r'isPrimitiveType is true for $-prefixed types', () {
      expect(HierarchyOccurrence.isPrimitiveType(r'$mux'), isTrue);
      expect(HierarchyOccurrence.isPrimitiveType(r'$and'), isTrue);
    });

    test(r'isPrimitiveType is false for non-$-prefixed types', () {
      expect(HierarchyOccurrence.isPrimitiveType('FilterBank'), isFalse);
    });

    test('isPrimitiveType is false for empty string', () {
      expect(HierarchyOccurrence.isPrimitiveType(''), isFalse);
    });
  });

  group('HierarchyService search utilities', () {
    test('hasRegexChars is false for plain text', () {
      expect(HierarchyService.hasRegexChars('clk'), isFalse);
    });

    test('hasRegexChars detects glob and regex syntax', () {
      for (final query in ['c*', 'cl?', '[a-z]', '(a|b)', 'a+']) {
        expect(HierarchyService.hasRegexChars(query), isTrue);
      }
    });

    test('longestCommonPrefix finds shared prefix', () {
      expect(
        HierarchyService.longestCommonPrefix([
          'FilterBank/ch0',
          'FilterBank/ch1',
        ]),
        'FilterBank/ch',
      );
    });

    test('longestCommonPrefix returns null without a shared prefix', () {
      expect(HierarchyService.longestCommonPrefix([]), isNull);
      expect(HierarchyService.longestCommonPrefix(['abc', 'xyz']), isNull);
    });

    test('longestCommonPrefix is case-sensitive', () {
      expect(
        HierarchyService.longestCommonPrefix(['Filter/abc', 'Filter/abd']),
        'Filter/ab',
      );
    });
  });

  group('BaseHierarchyAdapter', () {
    test('fromTree immediately sets root', () {
      final service =
          BaseHierarchyAdapter.fromTree(HierarchyOccurrence(name: 'r'));

      expect(service.root.name, 'r');
    });
  });
}
