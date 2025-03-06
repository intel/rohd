// Copyright (C) 2022-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// redundancy_handler_test.dart
// Unit tests for redundancy handling.
//
// 2025 March 5
// Author: Gustavo A. Bonilla Gonzalez <gustavo.bonilla.gonzalez@intel.com>

import 'package:rohd/src/utilities/redundancy_handler.dart';
import 'package:test/test.dart';

void main() {
  // Parameterized test cases for different types of redundant parentheses
  final testCases = [
    {
      'type': 'Arithmetic',
      'input': 'result = ((a + b));',
      'expected': 'result = a + b;'
    },
    {
      'type': 'Logical',
      'input': 'result = ((a && b));',
      'expected': 'result = a && b;'
    },
    {
      'type': 'Conditional',
      'input': 'result = ((a) ? (b) : (c));',
      'expected': 'result = (a) ? b : c;'
    },
    {
      'type': 'Custom 1',
      'input': '''
        my_mod inst1(
          .a_0((a[0]))
        );''',
      'expected': '''
        my_mod inst1(
          .a_0(a[0])
        );'''
    },
    {
      'type': 'Custom 2',
      'input': 'assign a = (b & (c & (d & e)));',
      'expected': 'assign a = (b & (c & d & e));'
    },
    {
      'type': 'Bitwise',
      'input': 'result = ((a & b));',
      'expected': 'result = a & b;'
    },
    {
      'type': 'Concatenation',
      'input': 'result = ({a, b});',
      'expected': 'result = {a, b};'
    },
    {
      'type': 'Function Call',
      'input': 'result = func((a, b));',
      'expected': 'result = func(a, b);'
    },
    {
      'type': 'Assignment',
      'input': 'result = ((a));',
      'expected': 'result = a;'
    },
    {'type': 'Case', 'input': 'case ((a))', 'expected': 'case (a)'},
    {'type': 'None', 'input': 'result = a + b;', 'expected': 'result = a + b;'},
  ];

  for (final testCase in testCases) {
    test('${testCase['type']} redundant parentheses: ${testCase['input']}',
        () async {
      final svCode = RedundancyHandler.removeRedundancies(testCase['input']!);
      expect(svCode, equals(testCase['expected']));
    });
  }
}
