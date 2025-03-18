// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// redundancy_handler.dart
// Removes redundant usage of parentheses from SystemVerilog code strings.
//
// 2025 March 4
// Author: Gustavo A. Bonilla Gonzalez <gustavo.bonilla.gonzalez@intel.com>
//         Adan Baltazar Ortiz         <adan.baltazar.ortiz@intel.com>

/// A utility for ensuring generated code doesn't contain redundant parentheses.
///
/// "Redundant" refers to parentheses usage that doesn't change the order of
/// operations in a SystemVerilog expression. This utility is useful for
/// ensuring generated code is concise and readable.
class RedundancyHandler {
  /// Iteratively removes any unnecessary parentheses present in [svCode],
  /// returning a refactored SystemVerilog code string.
  static String removeRedundancies(String svCode) {
    var newSvCode = svCode;
    var bkpSvCode = svCode;

    do {
      bkpSvCode = newSvCode;
      newSvCode = _removeRedundantParentheses(newSvCode);
    } while (newSvCode != bkpSvCode);

    return newSvCode;
  }

  /// Applies a set of patterns to remove redundant parentheses from [svCode],
  /// returning a modified SystemVerilog code string.
  static String _removeRedundantParentheses(String svCode) {
    final parenthesesPatterns = [
      RegExp(r'\((\w+)\s*([\+\-\*\/])\s*(\w+)\)'), // Arithmetic
      RegExp(r'\((\w+)\s*(&&|\|\|)\s*(\w+)\)'), // Logical
      RegExp(
          r'\(\(([^()]+)\)\s*\?\s*\(([^()]+)\)\s*:\s*\(([^()]+)\)\)'), // Conditional
      RegExp(r'\((\w+)\s*([&\|^~])\s*(\w+)\)'), // Bitwise
      RegExp(r'\(\{([^}]+)\}\)'), // Concatenation & replication
      RegExp(r'(\w+)\(\(([^)]+)\)\)'), // Function call
      RegExp(r'(\w+)\s*=\s*\(\(([^)]+)\)\)'), // Assignment
      RegExp(r'case\s*\(\(([^)]+)\)\)') // Case
    ];

    final parenthesesReplacements = [
      (Match match) => '${match[1]} ${match[2]} ${match[3]}', // Arithmetic
      (Match match) => '${match[1]} ${match[2]} ${match[3]}', // Logical
      (Match match) =>
          '(${match[1]}) ? ${match[2]} : ${match[3]}', // Conditional
      (Match match) => '${match[1]} ${match[2]} ${match[3]}', // Bitwise
      (Match match) => '{${match[1]}}', // Concatenation & replication
      (Match match) => '${match[1]}(${match[2]})', // Function call
      (Match match) => '${match[1]} = ${match[2]}', // Assignment
      (Match match) => 'case (${match[1]})' // Case
    ];

    var newSvCode = svCode;

    for (var i = 0; i < parenthesesPatterns.length; i++) {
      newSvCode = newSvCode.replaceAllMapped(
          parenthesesPatterns[i], parenthesesReplacements[i]);
    }

    return newSvCode;
  }
}
