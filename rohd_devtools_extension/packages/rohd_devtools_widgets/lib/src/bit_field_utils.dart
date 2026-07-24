// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bit_field_utils.dart
// Shared bit-field parsing, formatting, and dialog utilities.
//
// 2025 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

/// A named bit-field definition within a bitvector signal.
class BitFieldDef {
  /// Display name for this field (e.g. "exponent", "mantissa").
  final String name;

  /// High bit (inclusive, MSB of the field).
  final int high;

  /// Low bit (inclusive, LSB of the field).
  final int low;

  const BitFieldDef({
    required this.name,
    required this.high,
    required this.low,
  });

  /// Width of this field in bits.
  int get width => high - low + 1;
}

/// Shared utilities for parsing and formatting bit-field definitions.
abstract final class BitFieldUtils {
  /// Number of elements/bits above which a confirmation pop-up is shown
  /// before expanding an array, struct, or bitvector.
  static const int expandThreshold = 8;

  /// Format a bit-range label from [startBit] and [width].
  ///
  /// Returns e.g. `[7:4]` for startBit=4, width=4 or `[0]` for width=1.
  static String formatBitRange(int startBit, int width) {
    final highBit = startBit + width - 1;
    return highBit == startBit ? '[$startBit]' : '[$highBit:$startBit]';
  }

  /// Parse a bit range string (`high:low`) or single bit index.
  ///
  /// Returns `(high, low)` clamped to `[0, maxBit]`, or `null` if invalid.
  static (int, int)? parseBitRange(String input, int maxBit) {
    if (input.contains(':')) {
      final parts = input.split(':');
      if (parts.length != 2) return null;
      final high = int.tryParse(parts[0].trim());
      final low = int.tryParse(parts[1].trim());
      if (high == null || low == null) return null;
      final h = high.clamp(0, maxBit);
      final l = low.clamp(0, maxBit);
      return h >= l ? (h, l) : (l, h);
    }
    final bit = int.tryParse(input);
    if (bit == null) return null;
    final clamped = bit.clamp(0, maxBit);
    return (clamped, clamped);
  }

  /// Parse multi-line field definitions into [BitFieldDef] objects.
  ///
  /// Accepted formats per line:
  /// - `name high:low` (e.g. `exponent 31:21`)
  /// - `name high` (single bit, e.g. `sign 31`)
  /// - `high:low` (unnamed, displayed as `[high:low]`)
  /// - `bit` (unnamed single bit, displayed as `[bit]`)
  static List<BitFieldDef> parseBitFieldDefs(String input, int maxBit) {
    final lines = input.split('\n');
    final fields = <BitFieldDef>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final tokens = _splitAsciiWhitespace(line);

      // Try: name high:low
      final namedRange = tokens.length == 2 && _isWord(tokens[0])
          ? _parseRangeToken(tokens[1])
          : null;
      if (namedRange != null) {
        final name = tokens[0];
        final a = namedRange.$1.clamp(0, maxBit);
        final b = namedRange.$2.clamp(0, maxBit);
        final high = a >= b ? a : b;
        final low = a >= b ? b : a;
        fields.add(BitFieldDef(name: name, high: high, low: low));
        continue;
      }

      // Try: name bit (single bit)
      final namedSingle = tokens.length == 2 &&
          _isWord(tokens[0]) &&
          _isUnsignedDecimal(tokens[1]);
      if (namedSingle) {
        final name = tokens[0];
        final bit = int.parse(tokens[1]).clamp(0, maxBit);
        fields.add(BitFieldDef(name: name, high: bit, low: bit));
        continue;
      }

      // Try: high:low (unnamed)
      final anonRange = tokens.length == 1 ? _parseRangeToken(tokens[0]) : null;
      if (anonRange != null) {
        final a = anonRange.$1.clamp(0, maxBit);
        final b = anonRange.$2.clamp(0, maxBit);
        final high = a >= b ? a : b;
        final low = a >= b ? b : a;
        fields.add(BitFieldDef(name: '[$high:$low]', high: high, low: low));
        continue;
      }

      // Try: single number (unnamed single bit)
      if (tokens.length == 1 && _isUnsignedDecimal(tokens[0])) {
        final bit = int.parse(tokens[0]).clamp(0, maxBit);
        fields.add(BitFieldDef(name: '[$bit]', high: bit, low: bit));
        continue;
      }
    }
    return fields;
  }

  static List<String> _splitAsciiWhitespace(String value) {
    final tokens = <String>[];
    var tokenStart = -1;
    for (var i = 0; i < value.length; i++) {
      if (_isAsciiWhitespace(value.codeUnitAt(i))) {
        if (tokenStart >= 0) {
          tokens.add(value.substring(tokenStart, i));
          tokenStart = -1;
        }
      } else if (tokenStart < 0) {
        tokenStart = i;
      }
    }
    if (tokenStart >= 0) {
      tokens.add(value.substring(tokenStart));
    }
    return tokens;
  }

  static (int, int)? _parseRangeToken(String value) {
    final separator = value.indexOf(':');
    if (separator <= 0 || separator != value.lastIndexOf(':')) {
      return null;
    }
    final highText = value.substring(0, separator);
    final lowText = value.substring(separator + 1);
    if (!_isUnsignedDecimal(highText) || !_isUnsignedDecimal(lowText)) {
      return null;
    }
    return (int.parse(highText), int.parse(lowText));
  }

  static bool _isWord(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final char = value.codeUnitAt(i);
      final isUppercase = char >= 65 && char <= 90;
      final isLowercase = char >= 97 && char <= 122;
      final isDigit = char >= 48 && char <= 57;
      final isUnderscore = char == 95;
      if (!isUppercase && !isLowercase && !isDigit && !isUnderscore) {
        return false;
      }
    }
    return true;
  }

  static bool _isUnsignedDecimal(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final char = value.codeUnitAt(i);
      if (char < 48 || char > 57) return false;
    }
    return true;
  }

  static bool _isAsciiWhitespace(int char) =>
      char == 9 ||
      char == 10 ||
      char == 11 ||
      char == 12 ||
      char == 13 ||
      char == 32;
}

/// Show a dialog to select a bit range for a signal.
///
/// Returns `(high, low)` or `null` if cancelled.
Future<(int, int)?> showBitRangeDialog(
  BuildContext context, {
  required String signalName,
  required int width,
}) async {
  final maxBit = width - 1;
  final controller = TextEditingController(text: '$maxBit:0');
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );

  final result = await showDialog<String>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) {
      return AlertDialog(
        title: Text(
          '$signalName  [$width bits]',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Bit range (high:low) or single bit',
            hintText: '$maxBit:0',
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (result == null || result.trim().isEmpty) return null;
  return BitFieldUtils.parseBitRange(result.trim(), maxBit);
}

/// Show a dialog to define named bit-field slices on a signal.
///
/// Returns the parsed [BitFieldDef] list, or `null` if cancelled/empty.
Future<List<BitFieldDef>?> showDefineBitFieldsDialog(
  BuildContext context, {
  required String signalName,
  required int width,
  List<BitFieldDef>? existingDefs,
}) async {
  final maxBit = width - 1;

  // Pre-fill with existing definitions if re-editing; append a trailing
  // newline and place the cursor at the end so the user can immediately
  // type additional fields without accidentally replacing existing ones.
  final hasExisting = existingDefs != null && existingDefs.isNotEmpty;
  final initialText = hasExisting
      ? '${existingDefs.map((f) {
          return f.high == f.low
              ? '${f.name} ${f.high}'
              : '${f.name} ${f.high}:${f.low}';
        }).join('\n')}\n'
      : 'field0 $maxBit:0';

  final controller = TextEditingController(text: initialText);
  if (hasExisting) {
    // Cursor at the end (after trailing newline) — ready for a new field.
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  } else {
    // First time: select all default text for easy replacement.
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  final result = await showDialog<String>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) {
      return AlertDialog(
        title: Text(
          '$signalName  [$width bits] — Define Fields',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 8,
            minLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'One field per line: name high:low',
              hintText: 'exponent $maxBit:${maxBit - 10}\n'
                  'mantissa ${maxBit - 11}:0',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (result == null || result.trim().isEmpty) return null;
  final fields = BitFieldUtils.parseBitFieldDefs(result, maxBit);
  return fields.isEmpty ? null : fields;
}
