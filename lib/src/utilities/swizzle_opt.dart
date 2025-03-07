// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// swizzle_opt.dart
// Repalces unnecessary swizzle operations from SystemVerilog code strings.
//
// 2025 March 6
// Author: Gustavo A. Bonilla Gonzalez <gustavo.bonilla.gonzalez@intel.com>
//         Adan Baltazar Ortiz         <adan.baltazar.ortiz@intel.com>

/// A utility for ensuring code doesn't contain unnecessary swizzle operations.
///
/// "Unnecessary swizzle operations" refer to all direct assignments between 1
/// dimension (packed) LogicArray and Logic of the same width, the optimized
/// code will contain simple assignments instead of swizzle conversions.
class SystemVerilogSwizzleOptimizer {
  /// Method to optimize assignments in SystemVerilog code present in [svCode],
  /// returning an optimized SystemVerilog code string.
  static String optimizeAssignments(String svCode) {
    // Split the code into lines for processing
    final lines = svCode.split('\n');
    final optimizedLines = <String>[];

    // A map to store variable widths
    final variableWidths = <String, int>{};

    for (final line in lines) {
      // Check for logic declarations to capture variable widths
      final declarationMatch =
          RegExp(r'logic\s*\[(\d+):(\d+)\]\s*(\w+);').firstMatch(line);
      if (declarationMatch != null) {
        final upperBound = int.parse(declarationMatch.group(1)!);
        final lowerBound = int.parse(declarationMatch.group(2)!);
        final varName = declarationMatch.group(3)!;
        final width = (upperBound - lowerBound).abs() + 1;
        variableWidths[varName] = width;
      }

      // Check if the line contains a swizzle conversion
      if (line.contains('= {') && line.contains('};')) {
        // Checking and optimizing line
        final optimizedLine = _optimizeLine(line, variableWidths);
        optimizedLines.add(optimizedLine);
      } else {
        optimizedLines.add(line);
      }
    }

    // Join the optimized lines back into a single string
    return optimizedLines.join('\n');
  }

  /// Method to optimize a single line of SystemVerilog code
  static String _optimizeLine(String line, Map<String, int> variableWidths) {
    var optimizedLine = line;
    var unnecesarySwizzleDetected = false;

    // Example logic to identify and optimize swizzle conversions
    optimizedLine = optimizedLine
        .replaceAllMapped(RegExp(r'(\w+)\s*=\s*{\s*(\w+)\s*};'), (match) {
      final lhs = match.group(1)!;
      final rhs = match.group(2)!;

      // Check if the widths match for direct assignment
      if (variableWidths.containsKey(lhs) &&
          variableWidths.containsKey(rhs) &&
          variableWidths[lhs] == variableWidths[rhs]) {
        unnecesarySwizzleDetected = true;
      }

      // Transform swizzle conversion to direct assignment
      return '$lhs = $rhs;';
    });

    if (unnecesarySwizzleDetected) {
      return optimizedLine;
    } else {
      return line;
    }
  }
}
