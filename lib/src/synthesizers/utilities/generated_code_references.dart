// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// generated_code_references.dart
// Finds emitted expression locations for source tracing.
//
// 2026 November 19
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Finds the first code occurrence of each expression, ignoring comments and
/// string literals. Results use 1-based line and column positions.
Map<String, String> generatedCodeReferencePositions(
  String text,
  Iterable<String> expressions,
) {
  final byIdentifier = <String, List<String>>{};
  final identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*');
  for (final expression in expressions.toSet()) {
    final match = identifier.firstMatch(expression);
    if (match != null) {
      (byIdentifier[match.group(0)!] ??= []).add(expression);
    }
  }
  if (byIdentifier.isEmpty) {
    return {};
  }

  bool isIdentifier(int char) =>
      char >= 65 && char <= 90 ||
      char >= 97 && char <= 122 ||
      char >= 48 && char <= 57 ||
      char == 95 ||
      char == 36;

  final positions = <String, String>{};
  var line = 1;
  var column = 1;
  var lineComment = false;
  var blockComment = false;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final char = text.codeUnitAt(i);
    final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : -1;
    if (char == 10) {
      line++;
      column = 1;
      lineComment = false;
      continue;
    }
    if (lineComment) {
      column++;
      continue;
    }
    if (blockComment) {
      if (char == 42 && next == 47) {
        blockComment = false;
        i++;
        column++;
      }
    } else if (quoted) {
      if (char == 34 && !escaped) {
        quoted = false;
      }
      escaped = char == 92 && !escaped;
    } else if (char == 47 && next == 47) {
      lineComment = true;
      i++;
      column++;
    } else if (char == 47 && next == 42) {
      blockComment = true;
      i++;
      column++;
    } else if (char == 34) {
      quoted = true;
      escaped = false;
    } else if (isIdentifier(char) &&
        (i == 0 ||
            (!isIdentifier(text.codeUnitAt(i - 1)) &&
                text.codeUnitAt(i - 1) != 46))) {
      var end = i + 1;
      while (end < text.length && isIdentifier(text.codeUnitAt(end))) {
        end++;
      }
      final candidates = byIdentifier[text.substring(i, end)];
      if (candidates != null) {
        for (final expression in candidates) {
          final after = i + expression.length;
          if (!positions.containsKey(expression) &&
              text.startsWith(expression, i) &&
              (after == text.length || !isIdentifier(text.codeUnitAt(after)))) {
            positions[expression] = '$line:$column';
          }
        }
      }
    }
    column++;
  }
  return positions;
}
