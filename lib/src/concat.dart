// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// concat.dart
// List concatenation extensions.
//
// 2026 November 4
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Deprecated aliases remain through the 0.7.x migration window.
// ignore_for_file: remove_deprecations_in_breaking_versions

import 'package:rohd/rohd.dart';

/// Deprecated module alias for [Concat].
///
/// The legacy default instance name is retained for generated output
/// compatibility.
@Deprecated('Use Concat instead.')
class Swizzle extends Concat {
  /// Constructs a deprecated [Swizzle] module.
  @Deprecated('Use Concat instead.')
  Swizzle(super.signals, {super.name = 'swizzle'});
}

/// Provides concatenation utilities for lists of [Logic]s.
extension LogicConcat on List<Logic> {
  /// Concatenates signals with index 0 as the most significant bits.
  ///
  /// This matches SystemVerilog's `{}` notation.
  Logic concat() {
    final onlyNonZero = _onlyNonZeroWidthSignal();
    if (onlyNonZero != null) {
      return onlyNonZero;
    }
    return length == 1 ? first : Concat(this).out;
  }

  /// Concatenates signals with index 0 as the least significant bits.
  Logic rconcat() {
    final onlyNonZero = _onlyNonZeroWidthSignal();
    if (onlyNonZero != null) {
      return onlyNonZero;
    }
    return length == 1 ? first : Concat(reversed.toList(growable: false)).out;
  }

  /// Deprecated alias for [concat].
  @Deprecated('Use concat() instead.')
  Logic swizzle() => concat();

  /// Deprecated alias for [rconcat].
  @Deprecated('Use rconcat() instead.')
  Logic rswizzle() => rconcat();

  /// Returns the sole non-zero-width signal when this list has exactly one,
  /// otherwise `null`. Avoids creating a [Concat] for `{a}`-style cases that
  /// include zero-width companions.
  Logic? _onlyNonZeroWidthSignal() {
    Logic? only;
    for (final signal in this) {
      if (signal.width > 0) {
        if (only != null) {
          return null;
        }
        only = signal;
      }
    }
    return only;
  }
}

/// Provides concatenation utilities for lists of [LogicValue]s.
extension LogicValueConcat on List<LogicValue> {
  /// Concatenates values with index 0 as the most significant bits.
  ///
  /// This matches SystemVerilog's `{}` notation.
  LogicValue concat() => length == 1 ? first : LogicValue.ofIterable(reversed);

  /// Concatenates values with index 0 as the least significant bits.
  LogicValue rconcat() => length == 1 ? first : LogicValue.ofIterable(this);

  /// Deprecated alias for [concat].
  @Deprecated('Use concat() instead.')
  LogicValue swizzle() => concat();

  /// Deprecated alias for [rconcat].
  @Deprecated('Use rconcat() instead.')
  LogicValue rswizzle() => rconcat();
}
