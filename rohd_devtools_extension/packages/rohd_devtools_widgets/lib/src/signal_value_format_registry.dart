// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_format_registry.dart
// Shared signal display-format preferences and value formatting.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd/rohd.dart'
    show LogicValue, LogicValueConstructionException;
import 'package:rohd_hierarchy/rohd_hierarchy.dart'
    show OccurrenceAddress, OccurrenceTrie;

/// The available display formats for signal values.
enum SignalValueFormat {
  /// The source waveform representation.
  waveform,

  /// A binary representation.
  binary,

  /// A hexadecimal representation.
  hexadecimal,

  /// An unsigned decimal representation.
  unsignedDecimal,

  /// A two's-complement signed decimal representation.
  signedDecimal,

  /// An octal representation.
  octal,

  /// An ASCII representation.
  ascii,
}

/// A format preference for one signal occurrence address.
class SignalValueFormatPreference {
  /// Creates a preference for [address] using [format].
  SignalValueFormatPreference(
    this.address,
    this.format,
  );

  /// The occurrence address, including the signal index.
  final OccurrenceAddress address;

  /// The selected display format.
  final SignalValueFormat format;
}

/// Shared display-format preferences keyed by occurrence address.
///
/// Viewer packages publish [SignalValueFormat] values; embedded surfaces use
/// the same values without depending on viewer-local format enums.
class SignalValueFormatRegistry {
  SignalValueFormatRegistry._();

  static final _formatTrie = OccurrenceTrie<SignalValueFormat>();

  /// Notifies listeners whenever occurrence-format preferences change.
  static final changes = ValueNotifier<int>(0);

  /// Replaces all occurrence-format preferences with [preferences].
  static void update(Iterable<SignalValueFormatPreference> preferences) {
    _formatTrie.clear();
    for (final preference in preferences) {
      _formatTrie.set(preference.address, preference.format);
    }
    _notifyListeners();
  }

  /// Removes all occurrence-format preferences.
  static void clear() {
    if (_formatTrie.isEmpty) {
      return;
    }
    _formatTrie.clear();
    _notifyListeners();
  }

  /// Sets [format] for each signal occurrence in [addresses].
  static void setFormatFor(
    Iterable<OccurrenceAddress> addresses,
    SignalValueFormat format,
  ) {
    var changed = false;
    for (final address in addresses) {
      changed = (_formatTrie.set(address, format) != format) || changed;
    }
    if (changed) {
      _notifyListeners();
    }
  }

  /// Converts a serialized format name to its corresponding enum value.
  ///
  /// Returns `null` when [value] is not a known format name.
  static SignalValueFormat? formatFromString(String value) {
    for (final format in SignalValueFormat.values) {
      if (format.name == value) {
        return format;
      }
    }
    return null;
  }

  /// Converts [format] to its serialized format name.
  static String formatToString(SignalValueFormat format) => format.name;

  /// Returns the requested format for [address], or the waveform default.
  static SignalValueFormat formatFor(OccurrenceAddress address) {
    return formatForAny([address]);
  }

  /// Returns the first registered format matching [addresses].
  static SignalValueFormat formatForAny(
    Iterable<OccurrenceAddress?> addresses, {
    SignalValueFormat fallback = SignalValueFormat.waveform,
  }) {
    for (final address in addresses) {
      if (address == null) {
        continue;
      }
      final format = _formatTrie[address];
      if (format != null) {
        return format;
      }
    }
    return fallback;
  }

  static void _notifyListeners() => changes.value++;

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

  /// Formats a ROHD radix literal according to [format].
  static String formatValue(
    String value,
    SignalValueFormat format,
    int width,
  ) {
    final waveformValue = _waveformValue(value, width);
    if (waveformValue == null) {
      return _canonicalWaveformValue(value, width);
    }
    final (logicValue, canonical) = waveformValue;
    if (format == SignalValueFormat.waveform ||
        _containsUnknownDigits(canonical)) {
      return canonical;
    }
    return switch (format) {
      SignalValueFormat.binary => logicValue.toRadixString(
          leadingZeros: true,
          includeWidth: false,
          sepChar: '',
        ),
      SignalValueFormat.hexadecimal =>
        logicValue.toRadixString(radix: 16, sepChar: ''),
      SignalValueFormat.unsignedDecimal =>
        logicValue.toRadixString(radix: 10, includeWidth: false, sepChar: ''),
      SignalValueFormat.signedDecimal =>
        logicValue.toBigInt().toSigned(logicValue.width).toString(),
      SignalValueFormat.octal =>
        '0o${logicValue.toRadixString(radix: 8, includeWidth: false, sepChar: '')}',
      SignalValueFormat.ascii => String.fromCharCodes(
          List<int>.generate(
            ((logicValue.width + 7) ~/ 8).clamp(1, 32),
            (index) {
              final shift =
                  (((logicValue.width + 7) ~/ 8).clamp(1, 32) - index - 1) * 8;
              final code =
                  ((logicValue.toBigInt() >> shift) & BigInt.from(0xff))
                      .toInt();
              return code >= 0x20 && code <= 0x7e ? code : 0x2e;
            },
          ),
        ),
      SignalValueFormat.waveform => canonical,
    };
  }

  static (LogicValue, String)? _waveformValue(String value, int width) {
    final trimmed = value.trim().replaceAll('\u0000', '');
    if (trimmed.isEmpty || _containsUnknownDigits(trimmed)) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    final displayWidth = width > 0 ? width : 1;
    final isRadixLiteral = RegExp(r"^\d+'[bqodh]").hasMatch(lower);
    final digits = lower.startsWith('0x') || lower.startsWith('0b')
        ? lower.substring(2)
        : lower;
    final radix = lower.startsWith('0x')
        ? 'h'
        : lower.startsWith('0b')
            ? 'b'
            : isRadixLiteral
                ? lower[lower.indexOf("'") + 1]
                : digits.codeUnits.every(
                    (codeUnit) => codeUnit == 0x30 || codeUnit == 0x31,
                  )
                    ? 'b'
                    : digits.codeUnits.any(
                        (codeUnit) =>
                            (codeUnit >= 0x61 && codeUnit <= 0x66) ||
                            (codeUnit >= 0x41 && codeUnit <= 0x46),
                      )
                        ? 'h'
                        : 'd';
    final radixLiteral = isRadixLiteral ? lower : "$displayWidth'$radix$digits";
    try {
      final logicValue = LogicValue.ofRadixString(radixLiteral);
      return (
        logicValue,
        isRadixLiteral ? trimmed : logicValue.toString(),
      );
    } on LogicValueConstructionException {
      return null;
    }
  }

  static String _canonicalWaveformValue(String value, int width) {
    final waveformValue = _waveformValue(value, width);
    return waveformValue?.$2 ?? value.trim().replaceAll('\u0000', '');
  }
}
