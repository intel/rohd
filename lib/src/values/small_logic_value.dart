// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// small_logic_value.dart
// Definition for a logical value where the width is less
// than or equal to the size of an int.
//
// 2022 March 28
// Author: Max Korbel <max.korbel@intel.com>

part of 'values.dart';

/// A [LogicValue] whose number of bits is less than or equal to the size of
/// an int.
///
/// The implementation uses two ints to represent the 4-value value.  Each 0 and
/// 1 bit in [_value] represents a 0 or 1, respectively, if the corresponding
/// bit in [_invalid] is 0; otherwise, each 0 and 1 bit in [_value] represents
/// a x or z, respectively.
///
/// | [_value]  | [_invalid] | 4-value |
/// |-----------|------------|---------|
/// | 0         | 0          | 0       |
/// | 1         | 0          | 1       |
/// | 0         | 1          | x       |
/// | 1         | 1          | z       |
///
class _SmallLogicValue extends LogicValue {
  // Each 0/1 bit in value is 0/1 if !invalid, else is x/z

  final int _value;
  final int _invalid;

  int get _mask => _maskOfWidth(width);
  static final Map<int, int> _masksOfWidth = HashMap();
  static int _maskOfWidth(int width) {
    if (!_masksOfWidth.containsKey(width)) {
      _masksOfWidth[width] =
          (oneSllBy(width) - 1).toUnsigned(width).toSigned(INT_BITS);
    }
    return _masksOfWidth[width]!;
  }

  /// Constructs a new [_SmallLogicValue], intended to hold values
  /// between 1 and [INT_BITS] bits, inclusive.
  ///
  /// Set [allowInefficientRepresentation] to `true` to bypass
  /// inefficient representation assertions.
  const _SmallLogicValue(int value, int invalid, super.width,
      {bool allowInefficientRepresentation = false})
      : assert(width <= INT_BITS,
            '_SmallLogicValue should have low number of bits ($width found)'),
        assert(width != 0,
            '_SmallLogicValue should have at least one bit ($width found)'),
        assert(
            allowInefficientRepresentation ||
                !(((value & ((1 << width - 1) * 2) - 1) ==
                            ((1 << width - 1) * 2) - 1 ||
                        (value & ((1 << width - 1) * 2) - 1) == 0) &&
                    ((invalid & ((1 << width - 1) * 2) - 1) ==
                            ((1 << width - 1) * 2) - 1 ||
                        (invalid & ((1 << width - 1) * 2) - 1) == 0)),
            'Should not be expressable as filled: '
            '(value: $value, invalid: $invalid)'),
        _value = (((1 << width - 1) * 2) - 1) & value,
        _invalid = (((1 << width - 1) * 2) - 1) & invalid,
        super._();

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValue) {
      return other == this;
    }

    if (other is! _SmallLogicValue) {
      return false;
    }

    return _value == other._value && _invalid == other._invalid;
  }

  @override
  int get _hashCode => _value.hashCode ^ _invalid.hashCode ^ width.hashCode;

  @override
  LogicValue _getIndex(int index) {
    final bitValue = ((_value >> index) & 1) == 1;
    final bitInvalid = ((_invalid >> index) & 1) == 1;
    return _bitsToLogicValue(bitValue, bitInvalid);
  }

  @override
  LogicValue _getRange(int start, int end) {
    final newWidth = end - start;
    return LogicValue._smallLogicValueOrFilled(
      (_value >> start) & _maskOfWidth(newWidth),
      (_invalid >> start) & _maskOfWidth(newWidth),
      newWidth,
    );
  }

  @override
  LogicValue get reversed => LogicValue.ofIterable(toList().reversed);

  @override
  bool get isValid => _invalid == 0;

  @override
  bool get isFloating => (_invalid == _mask) && (_value == _mask);

  @override
  BigInt toBigInt() => BigInt.from(toInt()).toUnsigned(width);

  @override
  int toInt() {
    if (_invalid != 0) {
      throw Exception('Cannot convert invalid LogicValue to int: $this');
    }
    return _value.toSigned(INT_BITS);
  }

  @override
  LogicValue operator ~() => LogicValue._smallLogicValueOrFilled(
      ~_value & ~_invalid & _mask, _invalid, width);

  @override
  LogicValue _and2(LogicValue other) {
    assert(other is _SmallLogicValue, 'Will always be a _SmallLogicValue');
    other as _SmallLogicValue;
    final eitherInvalid = _invalid | other._invalid;
    final eitherZero =
        (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return LogicValue._smallLogicValueOrFilled(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, width);
  }

  @override
  LogicValue _or2(LogicValue other) {
    assert(other is _SmallLogicValue, 'Will always be a _SmallLogicValue');
    other as _SmallLogicValue;
    final eitherInvalid = _invalid | other._invalid;
    final eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return LogicValue._smallLogicValueOrFilled(
        eitherOne, eitherInvalid & ~eitherOne, width);
  }

  @override
  LogicValue _xor2(LogicValue other) {
    assert(other is _SmallLogicValue, 'Will always be a _SmallLogicValue');
    other as _SmallLogicValue;
    final eitherInvalid = _invalid | other._invalid;
    return LogicValue._smallLogicValueOrFilled(
        (_value ^ other._value) & ~eitherInvalid, eitherInvalid, width);
  }

  @override
  LogicValue _triState2(LogicValue other) {
    assert(other is _SmallLogicValue, 'Will always be a _SmallLogicValue');
    other as _SmallLogicValue;

    final oppositeValids =
        ~_invalid & ~other._invalid & (_value ^ other._value);

    final newValue = _value & other._value & ~oppositeValids & _mask;
    final newInvalid = ((_invalid & other._invalid) |
            (~_value & _invalid) |
            (~other._value & other._invalid) |
            oppositeValids) &
        _mask;

    return LogicValue._smallLogicValueOrFilled(newValue, newInvalid, width);
  }

  @override
  LogicValue and() => (~_value & ~_invalid) & _mask != 0
      ? LogicValue.zero
      : !isValid
          ? LogicValue.x
          : LogicValue.one;

  @override
  LogicValue or() => (_value ^ _invalid) & _value != 0
      ? LogicValue.one
      : !isValid
          ? LogicValue.x
          : LogicValue.zero;

  @override
  LogicValue xor() {
    if (!isValid) {
      return LogicValue.x;
    }
    var shiftedValue = _value;
    var result = 0;
    while (shiftedValue != 0) {
      result ^= shiftedValue & 1;
      shiftedValue >>= 1;
    }
    return result == 0 ? LogicValue.zero : LogicValue.one;
  }

  @override
  LogicValue _shiftLeft(int shamt) => LogicValue._smallLogicValueOrFilled(
      (_value << shamt) & _mask, (_invalid << shamt) & _mask, width);

  @override
  LogicValue _shiftRight(int shamt) => LogicValue._smallLogicValueOrFilled(
      _value >>> shamt, _invalid >>> shamt, width);

  @override
  LogicValue _shiftArithmeticRight(int shamt) {
    final upperMostBit = this[-1];

    // bits affected by the sign
    final upperMask = ~_maskOfWidth(width - shamt);

    var value = _value >>> shamt;
    if (upperMostBit == LogicValue.one) {
      value |= upperMask;
    }

    var invalid = _invalid >>> shamt;

    // if uppermost bit is invalid, then turn the shifted bits into X's
    if (!upperMostBit.isValid) {
      // for affected bits of value: zero out value
      value &= _mask >>> shamt;

      // for affected bits of invalid: make sure they are high
      invalid |= upperMask;
    }

    return LogicValue._smallLogicValueOrFilled(value, invalid, width);
  }

  @override
  BigInt get _bigIntInvalid =>
      BigInt.from(_invalid) & _BigLogicValue._maskOfWidth(width);

  @override
  BigInt get _bigIntValue =>
      BigInt.from(_value) & _BigLogicValue._maskOfWidth(width);

  @override
  int get _intInvalid => _invalid;

  @override
  int get _intValue => _value;

  @override
  bool get isZero => _value == 0 && _invalid == 0;
}
