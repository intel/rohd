// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// const.dart
// Definition of signals with constant values.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

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

  /// Constructs a [Const] with the specified value.
  ///
  /// [val] should be processable by [LogicValue.of].
  ///
  /// If a [width] is provided, the [Const] will be that width.  If not, and
  /// [val] is a [LogicValue], the [Const] will be the width of [val].
  /// Otherwise, the [Const] will be 1 bit wide.
  Const(dynamic val, {int? width, bool fill = false})
      : super(
          name: 'const_$val',
          width: width ?? (val is LogicValue ? val.width : 1),
          // we don't care about maintaining this node unless necessary
          naming: Naming.unnamed,
        ) {
    _wire
      ..put(val, fill: fill, signalName: name)
      ..makeImmutable(this, reason: _unassignableMessage);

    makeUnassignable(reason: _unassignableMessage);
  }

  @override
  Const clone({String? name}) => Const(value, width: width);

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
