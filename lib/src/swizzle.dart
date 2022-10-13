/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// swizzle_test.dart
/// Tests for swizzling values
///
/// 2022 January 6
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// Allows lists of [Logic]s to be swizzled.
extension LogicSwizzle on List<Logic> {
  /// Performs a concatenation operation on the list of signals, where index 0
  /// of this list is the *most* significant bit(s).
  ///
  /// This is the one you should use if you're writing something like
  /// SystemVerilog's `{}` notation. If you call [swizzle] on `[a, b, c]` you
  /// would get a single output [Logic] where the bits in `a` are the most
  /// significant (highest) bits.
  ///
  /// If you want the opposite, check out [rswizzle].
  Logic swizzle() => Swizzle(this).out;

  /// Performs a concatenation operation on the list of signals, where index 0
  /// of this list is the *least* significant bit(s).
  ///
  /// This is the one you should probably use if you're trying to concatenate a
  /// generated [List] of signals. If you call [rswizzle] on `[a, b, c]` you
  /// would get a single output [Logic] where the bits in `a` are the least
  /// significant (lowest) bits.
  ///
  /// If you want the opposite, check out [swizzle].
  Logic rswizzle() => Swizzle(reversed.toList()).out;
}

/// Allows lists of [LogicValue]s to be swizzled.
extension LogicValueSwizzle on List<LogicValue> {
  /// Performs a concatenation operation on the list of signals, where index 0
  /// of this list is the *most* significant bit.
  ///
  /// This is the one you should use if you're writing something like
  /// SystemVerilog's `{}` notation. If you call [swizzle] on `[a, b, c]` you
  /// would get a single output [LogicValue] where the bits in `a` are the
  /// most significant (highest) bits.
  ///
  /// If you want the opposite, check out [rswizzle].
  LogicValue swizzle() => LogicValue.of(reversed);

  /// Performs a concatenation operation on the list of signals, where index 0
  /// of this list is the *least* significant bit.
  ///
  /// This is the one you should probably use if you're trying to concatenate a
  /// generated [List] of signals. If you call [rswizzle] on `[a, b, c]` you
  /// would get a single output [LogicValue] where the bits in `a` are the
  /// least significant (lowest) bits.
  ///
  /// If you want the opposite, check out [swizzle].
  LogicValue rswizzle() => LogicValue.of(this);
}

/// Performs a concatenation operation on the list of signals, where index 0 of
/// [signals] is the *most* significant bit(s).
///
/// This is the one you should use if you're writing something like
/// SystemVerilog's `{}` notation. If you write `swizzle([a, b, c])` you would
/// get a single output [Logic] where the bits in `a` are the most significant
/// (highest) bits.
///
/// If you want the opposite, check out [rswizzle()].
@Deprecated('Use `List<Logic>.swizzle()` instead')
Logic swizzle(List<Logic> signals) => signals.swizzle();

/// Performs a concatenation operation on the list of signals, where index 0 of
/// [signals] is the *least* significant bit(s).
///
/// This is the one you should probably use if you're trying to concatenate a
/// generated [List] of signals. If you write `rswizzle([a, b, c])` you would
/// get a single output [Logic] where the bits in `a` are the least significant
/// (lowest) bits.
///
/// If you want the opposite, check out [swizzle()].
@Deprecated('Use `List<Logic>.rswizzle()` instead')
Logic rswizzle(List<Logic> signals) => signals.rswizzle();
