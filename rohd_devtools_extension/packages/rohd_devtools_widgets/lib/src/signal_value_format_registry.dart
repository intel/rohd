// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_format_registry.dart
// Shared signal display-format preferences and value formatting.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart' show LogicValue;

/// Shared display-format preferences keyed by signal hierarchy path.
///
/// Viewer packages publish format names from their local format enums; other
/// embedded surfaces read the same names without depending on those enums.
class SignalValueFormatRegistry {
  SignalValueFormatRegistry._();

  /// Current occurrence-format preferences.
  static final formats = ValueNotifier<Map<String, String>>(
    const <String, String>{},
  );

  /// Replaces the current occurrence-format preferences.
  static void update(Map<String, String> value) {
    if (mapEquals(formats.value, value)) {
      return;
    }
    formats.value = Map<String, String>.unmodifiable(value);
  }

  /// Sets [format] for each signal occurrence in [signalPaths].
  static void setFormatFor(Iterable<String> signalPaths, String format) {
    final updated = Map<String, String>.from(formats.value);
    for (final signalPath in signalPaths) {
      updated[signalPath] = format;
    }
    update(updated);
  }

  /// Returns the requested format name, or the waveform default.
  static String formatFor(String signalPath) {
    return formatForAny([signalPath]);
  }

  /// Returns the first registered format matching [signalPaths].
  ///
  /// A waveform row may only have its transport ID while another surface has
  /// the canonical hierarchy path. Consumers should provide both identities
  /// in canonical-path-first order.
  static String formatForAny(
    Iterable<String?> signalPaths, {
    String fallback = 'waveform',
  }) {
    for (final signalPath in signalPaths) {
      if (signalPath == null || signalPath.isEmpty) {
        continue;
      }
      final direct = formats.value[signalPath];
      if (direct != null) {
        return direct;
      }
      final normalizedPath = _normalizePath(signalPath);
      for (final entry in formats.value.entries) {
        if (_normalizePath(entry.key) == normalizedPath) {
          return entry.value;
        }
      }
      final suffixFormats = formats.value.entries
          .where(
            (entry) =>
                _hasWholePathSuffix(_normalizePath(entry.key), normalizedPath),
          )
          .map((entry) => entry.value)
          .toSet();
      if (suffixFormats.length == 1) {
        return suffixFormats.single;
      }
    }
    return fallback;
  }

  static String _normalizePath(String path) => path
      .replaceAll('.', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceFirst(RegExp(r'^/+|/+$'), '');

  static bool _hasWholePathSuffix(String first, String second) {
    final firstSegments = first.split('/');
    final secondSegments = second.split('/');
    var matchingSegments = 0;
    while (matchingSegments < firstSegments.length &&
        matchingSegments < secondSegments.length &&
        firstSegments[firstSegments.length - matchingSegments - 1] ==
            secondSegments[secondSegments.length - matchingSegments - 1]) {
      matchingSegments++;
    }
    return matchingSegments >= 2;
  }

  static bool _containsUnknownDigits(String value) {
    final lower = value.toLowerCase();
    final apostrophe = lower.indexOf("'");
    final digits = apostrophe > 0 && apostrophe + 2 <= lower.length
        ? lower.substring(apostrophe + 2)
        : lower.startsWith('0x') || lower.startsWith('0b')
        ? lower.substring(2)
        : lower;
    return digits.contains('x') || digits.contains('z');
  }

  /// Formats a ROHD radix literal according to a published format name.
  static String formatValue(String value, String format, int width) {
    final canonical = _canonicalWaveformValue(value, width);
    if (format == 'waveform' || _containsUnknownDigits(canonical)) {
      return canonical;
    }
    final lower = canonical.toLowerCase();
    final apostrophe = lower.indexOf("'");
    final bareDigits = lower.startsWith('0x') || lower.startsWith('0b')
        ? lower.substring(2)
        : lower;
    final radix = apostrophe > 0 && apostrophe + 1 < lower.length
        ? switch (lower[apostrophe + 1]) {
            'b' => 2,
            'o' || 'q' => 8,
            'd' => 10,
            'h' => 16,
            _ => null,
          }
        : lower.startsWith('0x')
        ? 16
        : lower.startsWith('0b')
        ? 2
        : bareDigits.codeUnits.every(
            (codeUnit) => codeUnit == 0x30 || codeUnit == 0x31,
          )
        ? 2
        : bareDigits.codeUnits.any(
            (codeUnit) =>
                (codeUnit >= 0x61 && codeUnit <= 0x66) ||
                (codeUnit >= 0x41 && codeUnit <= 0x46),
          )
        ? 16
        : 10;
    final digits = apostrophe > 0 && radix != null
        ? lower.substring(apostrophe + 2)
        : lower.startsWith('0x') || lower.startsWith('0b')
        ? lower.substring(2)
        : lower;
    final numeric = radix == null
        ? null
        : BigInt.tryParse(digits, radix: radix);
    if (numeric == null) return canonical;
    final displayWidth = width > 0 ? width : 1;
    return switch (format) {
      'binary' => numeric.toRadixString(2).padLeft(displayWidth, '0'),
      'hexadecimal' => LogicValue.ofBigInt(numeric, displayWidth).toString(),
      'unsignedDecimal' => numeric.toString(),
      'signedDecimal' =>
        (numeric >= (BigInt.one << (displayWidth - 1))
                ? numeric - (BigInt.one << displayWidth)
                : numeric)
            .toString(),
      'octal' => '0o${numeric.toRadixString(8)}',
      'ascii' => String.fromCharCodes(
        List<int>.generate(((displayWidth + 7) ~/ 8).clamp(1, 32), (index) {
          final shift =
              (((displayWidth + 7) ~/ 8).clamp(1, 32) - index - 1) * 8;
          final code = ((numeric >> shift) & BigInt.from(0xff)).toInt();
          return code >= 0x20 && code <= 0x7e ? code : 0x2e;
        }),
      ),
      _ => canonical,
    };
  }

  static String _canonicalWaveformValue(String value, int width) {
    final trimmed = value.trim().replaceAll('\u0000', '');
    if (trimmed.isEmpty || _containsUnknownDigits(trimmed)) {
      return trimmed;
    }
    final lower = trimmed.toLowerCase();
    if (RegExp(r"^\d+'[bqodh]").hasMatch(lower)) {
      return trimmed;
    }
    final digits = lower.startsWith('0x') || lower.startsWith('0b')
        ? lower.substring(2)
        : lower;
    final radix = lower.startsWith('0x')
        ? 16
        : lower.startsWith('0b')
        ? 2
        : digits.codeUnits.every(
            (codeUnit) => codeUnit == 0x30 || codeUnit == 0x31,
          )
        ? 2
        : digits.codeUnits.any(
            (codeUnit) =>
                (codeUnit >= 0x61 && codeUnit <= 0x66) ||
                (codeUnit >= 0x41 && codeUnit <= 0x46),
          )
        ? 16
        : 10;
    final numeric = BigInt.tryParse(digits, radix: radix);
    if (numeric == null) {
      return trimmed;
    }
    return LogicValue.ofBigInt(numeric, width > 0 ? width : 1).toString();
  }
}
