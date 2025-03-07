// Copyright (C) 2022-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// swizzle_opt_test.dart
// Unit tests for swizzle optimization.
//
// 2025 March 6
// Author: Gustavo A. Bonilla Gonzalez <gustavo.bonilla.gonzalez@intel.com>
//         Adan Baltazar Ortiz         <adan.baltazar.ortiz@intel.com>

import 'package:rohd/src/utilities/swizzle_opt.dart'; // Adjust the import path as necessary
import 'package:test/test.dart';

void main() {
  group('SystemVerilogOptimizer', () {
    test('optimizes simple swizzle conversion', () {
      const input = '''
module example1;
  logic [7:0] myArray;
  logic [7:0] myValue;

  initial begin
    myArray = {myValue};
  end
endmodule
''';

      const expectedOutput = '''
module example1;
  logic [7:0] myArray;
  logic [7:0] myValue;

  initial begin
    myArray = myValue;
  end
endmodule
''';

      expect(SystemVerilogSwizzleOptimizer.optimizeAssignments(input),
          equals(expectedOutput));
    });

    test('does not optimize when widths do not match', () {
      const input = '''
module example2;
  logic [7:0] myArray;
  logic [3:0] myValue;

  initial begin
    myArray = {myValue};
  end
endmodule
''';

      // Expect no change since widths do not match
      expect(SystemVerilogSwizzleOptimizer.optimizeAssignments(input),
          equals(input));
    });

    test('handles complex expressions without change', () {
      const input = '''
module example3;
  logic [7:0] myArray;
  logic [3:0] myValue1, myValue2;

  initial begin
    myArray = {myValue1, myValue2};
  end
endmodule
''';

      // Expect no change for complex expressions
      expect(SystemVerilogSwizzleOptimizer.optimizeAssignments(input),
          equals(input));
    });

    test('optimizes multiple assignments', () {
      const input = '''
module example4;
  logic [7:0] myArray1;
  logic [7:0] myArray2;
  logic [7:0] myValue1;
  logic [7:0] myValue2;

  initial begin
    myArray1 = {myValue1};
    myArray2 = {myValue2};
  end
endmodule
''';

      const expectedOutput = '''
module example4;
  logic [7:0] myArray1;
  logic [7:0] myArray2;
  logic [7:0] myValue1;
  logic [7:0] myValue2;

  initial begin
    myArray1 = myValue1;
    myArray2 = myValue2;
  end
endmodule
''';

      expect(SystemVerilogSwizzleOptimizer.optimizeAssignments(input),
          equals(expectedOutput));
    });
  });
}
