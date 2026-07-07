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

      // Try: name high:low
      final namedRange = RegExp(r'^(\w+)\s+(\d+):(\d+)$').firstMatch(line);
      if (namedRange != null) {
        final name = namedRange.group(1)!;
        final a = int.parse(namedRange.group(2)!).clamp(0, maxBit);
        final b = int.parse(namedRange.group(3)!).clamp(0, maxBit);
        final high = a >= b ? a : b;
        final low = a >= b ? b : a;
        fields.add(BitFieldDef(name: name, high: high, low: low));
        continue;
      }

      // Try: name bit (single bit)
      final namedSingle = RegExp(r'^(\w+)\s+(\d+)$').firstMatch(line);
      if (namedSingle != null) {
        final name = namedSingle.group(1)!;
        final bit = int.parse(namedSingle.group(2)!).clamp(0, maxBit);
        fields.add(BitFieldDef(name: name, high: bit, low: bit));
        continue;
      }

      // Try: high:low (unnamed)
      final anonRange = RegExp(r'^(\d+):(\d+)$').firstMatch(line);
      if (anonRange != null) {
        final a = int.parse(anonRange.group(1)!).clamp(0, maxBit);
        final b = int.parse(anonRange.group(2)!).clamp(0, maxBit);
        final high = a >= b ? a : b;
        final low = a >= b ? b : a;
        fields.add(BitFieldDef(name: '[$high:$low]', high: high, low: low));
        continue;
      }

      // Try: single number (unnamed single bit)
      final anonSingle = RegExp(r'^(\d+)$').firstMatch(line);
      if (anonSingle != null) {
        final bit = int.parse(anonSingle.group(1)!).clamp(0, maxBit);
        fields.add(BitFieldDef(name: '[$bit]', high: bit, low: bit));
        continue;
      }
    }
    return fields;
  }
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
