// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_cleaner_test.dart
// Tests for SvCleaner utility functions
//
// 2025 November 5
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/utilities/sv_cleaner.dart';
import 'package:test/test.dart';

void main() {
  group('SvCleaner', () {
    test('removes basic bit range annotations', () {
      const input = '''
assign out = {
a, /* 24:17 */
b, /* 16:13 */
c, /*    12 */
d  /* 11: 0 */
};''';

      const expected = '''assign out = {a,b,c,d};''';

      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, equals(expected));
    });

    test('preserves non-bit-range comments', () {
      const input = '''
// This is a regular comment
assign out = {
a, /* 7:0 */
b, /* 3 */
c  /* 15:8 */
}; // Another regular comment
/* This is a block comment that should stay */''';

      const expected = '''
// This is a regular comment
assign out = {a,b,c}; // Another regular comment
/* This is a block comment that should stay */''';

      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, equals(expected));
    });

    test('handles single bit annotations', () {
      const input = 'signal /* 5 */ <= other_signal;';
      const expected = 'signal<= other_signal;';

      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, equals(expected));
    });

    test('handles multi-digit bit ranges', () {
      const input = 'big_signal /* 123:45 */ <= other;';
      const expected = 'big_signal<= other;';

      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, equals(expected));
    });

    test('does not affect other SystemVerilog content', () {
      const input = '''
module test (
  input logic [7:0] a,
  output logic [15:0] b
);
  assign b = {a, /* 15:8 */ a /* 7:0 */};
  /* Regular comment */
  always_comb begin
    // Line comment
    if (condition) begin
      result = value;
    end
  end
endmodule''';

      // Should only remove the bit range annotations
      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, contains('input logic [7:0] a'));
      expect(result, contains('/* Regular comment */'));
      expect(result, contains('// Line comment'));
      expect(result, isNot(contains('/* 15:8 */')));
      expect(result, isNot(contains('/* 7:0 */')));
      expect(result, contains('{a,a}')); // Should remove space and annotations
    });

    test('handles empty input', () {
      final result = SvCleaner.removeSwizzleAnnotationComments('');
      expect(result, equals(''));
    });

    test('handles input without annotations', () {
      const input = '''
assign out = {
a,
b,
c
};''';

      const expected = '''
assign out = {a,
b,
c};''';

      final result = SvCleaner.removeSwizzleAnnotationComments(input);
      expect(result, equals(expected));
    });
  });
}
