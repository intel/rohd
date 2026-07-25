// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// const.dart
// Definition of signals with constant values.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Returns [preferredRadix] if it is supported for generated literals.
///
/// Throws a [LogicValueConversionException] for unsupported radices.
int? _validatePreferredRadix(int? preferredRadix) {
  if (preferredRadix != null &&
      !const {2, 8, 10, 16}.contains(preferredRadix)) {
    throw LogicValueConversionException(
        'Unsupported preferred radix: $preferredRadix');
  }

  return preferredRadix;
}

/// Creates an identifier-friendly name for a constant [value].
///
/// Fully known values use [preferredRadix], or decimal if none is
/// preferred. Values containing `x` or `z` use binary so no state is lost.
String _constName(LogicValue value, int? preferredRadix) {
  final radix = value.isValid ? preferredRadix ?? 10 : 2;
  final digits = value.toRadixString(
    radix: radix,
    includeWidth: false,
    sepChar: '',
  );
  final prefix = switch (radix) {
    2 => '0b',
    8 => '0o',
    10 => '',
    16 => '0x',
    _ => throw StateError('Unexpected radix: $radix'),
  };

  return 'const_$prefix$digits';
}

/// Represents a [Logic] that never changes value.
///
/// Attempts to assign, [put], or [inject] a new value throw an
/// [UnassignableException], including through another [Logic] driven by the
/// [Const].
class Const extends Logic {
  /// The explanation included when an attempt is made to modify a [Const].
  static const _unassignableMessage =
      'A `Const` value cannot be modified, including through another `Logic` '
      'driven by it.';

  /// The preferred radix for displaying this constant in generated outputs.
  ///
  /// Supported radices are binary (2), octal (8), decimal (10), and
  /// hexadecimal (16). If omitted, generated outputs select a radix
  /// automatically. A generator may fall back to another radix when the
  /// preferred radix cannot represent this constant's value.
  final int? preferredRadix;

  /// Constructs a [Const] with the specified value.
  ///
  /// [val] should be processable by [LogicValue.of].
  ///
  /// If a [width] is provided, the [Const] will be that width.  If not, and
  /// [val] is a [LogicValue], the [Const] will be the width of [val].
  /// Otherwise, the [Const] will be 1 bit wide.
  ///
  /// [preferredRadix] controls how the constant is displayed in generated
  /// outputs and its normalized name. Supported values are 2, 8, 10, and 16.
  /// If omitted, generated outputs select a radix automatically and the name
  /// uses decimal. Values containing `x` or `z` may fall back to binary.
  Const(
    dynamic val, {
    int? width,
    bool fill = false,
    int? preferredRadix,
  }) : this._(
          LogicValue.of(
            val,
            width: width ?? (val is LogicValue ? val.width : 1),
            fill: fill,
          ),
          preferredRadix: _validatePreferredRadix(preferredRadix),
        );

  /// Constructs a [Const] from an already normalized [value].
  Const._(LogicValue value, {required this.preferredRadix})
      : super(
          name: _constName(value, preferredRadix),
          width: value.width,
          // we don't care about maintaining this node unless necessary
          naming: Naming.unnamed,
        ) {
    _wire
      ..put(value, signalName: name)
      ..makeImmutable(this, reason: _unassignableMessage);

    makeUnassignable(reason: _unassignableMessage);
  }

  @override
  Const clone({String? name}) =>
      Const(value, width: width, preferredRadix: preferredRadix);

  @override
  void put(dynamic val, {bool fill = false}) =>
      throw UnassignableException(this, reason: _unassignableMessage);

  @override
  void inject(dynamic val, {bool fill = false}) =>
      throw UnassignableException(this, reason: _unassignableMessage);

  /// Verifies that [other] has the same width as this [Const].
  void _checkMatchingWidth(Logic other) {
    if (width != other.width) {
      throw PortWidthMismatchException.equalWidth(this, other);
    }
  }

  @override
  Logic operator ~() => Const(~value);

  @override
  Logic operator &(Logic other) {
    _checkMatchingWidth(other);

    if (other is Const) {
      return Const(value & other.value);
    } else if (value.isValid && value.isZero) {
      return this;
    }

    return And2Gate(this, other).out;
  }

  @override
  Logic operator |(Logic other) {
    _checkMatchingWidth(other);

    if (other is Const) {
      return Const(value | other.value);
    } else if (value.isValid &&
        value == LogicValue.filled(width, LogicValue.one)) {
      return this;
    }

    return Or2Gate(this, other).out;
  }

  @override
  Logic operator ^(Logic other) {
    _checkMatchingWidth(other);

    if (other is Const) {
      return Const(value ^ other.value);
    }

    return Xor2Gate(this, other).out;
  }

  @override
  Logic operator >>(dynamic other) {
    if (Logic._isZeroShiftAmount(other)) {
      return this;
    } else if (other is Logic && other is! Const) {
      return ARShift(this, other).out;
    }

    return Const(value >> (other is Const ? other.value : other));
  }

  @override
  Logic operator <<(dynamic other) {
    if (Logic._isZeroShiftAmount(other)) {
      return this;
    } else if (other is Logic && other is! Const) {
      return LShift(this, other).out;
    }

    return Const(value << (other is Const ? other.value : other));
  }

  @override
  Logic operator >>>(dynamic other) {
    if (Logic._isZeroShiftAmount(other)) {
      return this;
    } else if (other is Logic && other is! Const) {
      return RShift(this, other).out;
    }

    return Const(value >>> (other is Const ? other.value : other));
  }

  @override
  Logic and() => Const(value.and());

  @override
  Logic or() => Const(value.or());

  @override
  Logic xor() => Const(value.xor());

  @override
  Logic eq(dynamic other) {
    if (other is Logic) {
      _checkMatchingWidth(other);
      return other is Const
          ? Const(value.eq(other.value))
          : Equals(this, other).out;
    }

    return Const(value.eq(LogicValue.of(other, width: width)));
  }

  @override
  Logic neq(dynamic other) {
    if (other is Logic) {
      _checkMatchingWidth(other);
      return other is Const
          ? Const(value.neq(other.value))
          : NotEquals(this, other).out;
    }

    return Const(value.neq(LogicValue.of(other, width: width)));
  }
}
