// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bit_expansion_menu.dart
// Shared popup-menu items and dispatcher for the "Expand Bits" and
// "Define Bit Fields" actions. Used by all three surfaces that offer
// per-signal right-click menus: the waveform Signal-Selection overlay,
// the Selected-Signals panel, and the embedded Signal Details pane.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

import 'bit_field_utils.dart';

/// Popup-menu values used by the bit-expansion items.
///
/// Callers may match against these string constants when handling a
/// `showMenu<String>` result that includes bit-expansion items.
abstract final class BitExpansionMenuValues {
  /// Menu item: "Expand Bits [N]" — expand each bit (or a chosen range)
  /// as a synthesized 1-bit waveform.
  static const String expandBits = 'expand_bits';

  /// Menu item: "Define Bit Fields [N]..." — open a dialog that lets the
  /// user name arbitrary bit ranges.
  static const String defineFields = 'define_fields';
}

/// Result of a bit-expansion menu interaction after any follow-up dialog
/// has resolved. Returned by [resolveBitExpansionMenuValue].
sealed class BitExpansionAction {
  const BitExpansionAction();
}

/// User picked "Expand Bits" and (implicitly or via dialog) chose the bit
/// range `[bitEnd:bitStart]` to expand into single-bit synthesized
/// waveforms.
class BitExpandRangeAction extends BitExpansionAction {
  /// Low bit (inclusive) of the range to expand.
  final int bitStart;

  /// High bit (inclusive) of the range to expand.
  final int bitEnd;

  const BitExpandRangeAction(this.bitStart, this.bitEnd);
}

/// User picked "Define Bit Fields..." and entered a non-empty list of
/// named [BitFieldDef]s.
class BitDefineFieldsAction extends BitExpansionAction {
  /// The user-defined bit fields.
  final List<BitFieldDef> fields;

  const BitDefineFieldsAction(this.fields);
}

/// Build the standard pair of popup-menu items shown when right-clicking
/// a single multi-bit signal:
///
/// - **Expand Bits [width]**
/// - **Define Bit Fields [width]...**
///
/// Callers should typically append these items to their existing
/// `PopupMenuEntry<String>` list only when the signal selection contains
/// exactly one signal whose width is > 1.
///
/// The optional [includeDivider] inserts a [PopupMenuDivider] before the
/// items so they visually separate from preceding items.
List<PopupMenuEntry<String>> buildBitExpansionMenuItems({
  required int width,
  double fontSize = 13,
  double itemHeight = 32,
  bool includeDivider = false,
}) {
  return <PopupMenuEntry<String>>[
    if (includeDivider) const PopupMenuDivider(height: 8),
    PopupMenuItem<String>(
      height: itemHeight,
      value: BitExpansionMenuValues.expandBits,
      child: Text('Expand Bits [$width]', style: TextStyle(fontSize: fontSize)),
    ),
    PopupMenuItem<String>(
      height: itemHeight,
      value: BitExpansionMenuValues.defineFields,
      child: Text(
        'Define Bit Fields [$width]...',
        style: TextStyle(fontSize: fontSize),
      ),
    ),
  ];
}

/// Translate a popup-menu [value] returned by `showMenu<String>` into a
/// [BitExpansionAction], showing any follow-up dialog as needed.
///
/// Returns:
///   * [BitExpandRangeAction] when [value] is
///     [BitExpansionMenuValues.expandBits]. If [width] is at or below
///     [BitFieldUtils.expandThreshold] the full range `(0, width-1)` is
///     returned immediately. Otherwise [showBitRangeDialog] is invoked
///     and `null` is returned if the user cancels.
///   * [BitDefineFieldsAction] when [value] is
///     [BitExpansionMenuValues.defineFields]. [showDefineBitFieldsDialog]
///     is invoked; `null` is returned if the user cancels or enters no
///     fields.
///   * `null` for any other value (callers should handle their own
///     non-bit-expansion menu items first).
Future<BitExpansionAction?> resolveBitExpansionMenuValue(
  BuildContext context, {
  required String? value,
  required String signalName,
  required int width,
}) async {
  if (value == BitExpansionMenuValues.expandBits) {
    if (width <= BitFieldUtils.expandThreshold) {
      return BitExpandRangeAction(0, width - 1);
    }
    final parsed = await showBitRangeDialog(
      context,
      signalName: signalName,
      width: width,
    );
    if (parsed == null) return null;
    final (high, low) = parsed;
    return BitExpandRangeAction(low, high);
  }
  if (value == BitExpansionMenuValues.defineFields) {
    final fields = await showDefineBitFieldsDialog(
      context,
      signalName: signalName,
      width: width,
    );
    if (fields == null || fields.isEmpty) return null;
    return BitDefineFieldsAction(fields);
  }
  return null;
}
