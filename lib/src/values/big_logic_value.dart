/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// big_logic_value.dart
/// Definition for a logical value where all bits are the same value.
///
/// 2022 March 28
/// Author: Max Korbel <max.korbel@intel.com>
///

part of values;

/// Extends [BigInt] with utility functions that are useful for dealing with
/// large bit vectors and conversion between types.
extension BigLogicValueBigIntUtilities on BigInt {
  /// Returns this [BigInt] as an [int].
  ///
  /// Always interprets the number as unsigned, and thus never clamps to fit.
  int toIntUnsigned(int width) {
    if (width > LogicValue._INT_BITS) {
      throw Exception('Cannot convert to BigInt when width $width'
          ' is greater than ${LogicValue._INT_BITS}');
    } else if (width == LogicValue._INT_BITS) {
      // When width is 64, `BigInt.toInt()` will clamp values assuming that
      // it's a signed number.  To avoid that, if the width is 64, then do the
      // conversion in two 32-bit chunks and bitwise-or them together.
      const maskWidth = 32;
      final mask = _BigLogicValue._maskOfWidth(maskWidth);
      return (this & mask).toInt() |
          (((this >> maskWidth) & mask).toInt() << maskWidth);
    } else {
      return toInt();
    }
  }
}

/// A [LogicValue] whose number of bits is greater than the size of an [int].
///
/// The implementation is similar to [_SmallLogicValue], except it uses
/// [BigInt].
class _BigLogicValue extends LogicValue {
  late final BigInt _value;
  late final BigInt _invalid;

  BigInt get _mask => _maskOfWidth(width);
  static final Map<int, BigInt> _masksOfWidth = {};
  static BigInt _maskOfWidth(int width) {
    if (!_masksOfWidth.containsKey(width)) {
      _masksOfWidth[width] = (BigInt.one << width) - BigInt.one;
    }
    return _masksOfWidth[width]!;
  }

  /// Constructs a new [_SmallLogicValue], intended to hold values
  /// with more than [_INT_BITS] bits.
  ///
  /// Set [allowInefficientRepresentation] to `true` to bypass
  /// inefficient representation assertions.
  _BigLogicValue(BigInt value, BigInt invalid, int width,
      {bool allowInefficientRepresentation = false})
      : assert(width > LogicValue._INT_BITS,
            '_BigLogicValue should only be used for large values'),
        super._(width) {
    _value = _mask & value;
    _invalid = _mask & invalid;

    assert(
        allowInefficientRepresentation ||
            !((_value == _mask || _value == BigInt.zero) &&
                (_invalid == _mask || _invalid == BigInt.zero)),
        'Should not be expressable as filled');
  }

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValue) {
      return other == this;
    }
    if (other is! _BigLogicValue) {
      return false;
    }
    return _value == other._value && _invalid == other._invalid;
  }

  @override
  int get _hashCode => _value.hashCode ^ _invalid.hashCode;

  @override
  LogicValue _getIndex(int index) {
    final bitValue = (_value >> index).isOdd;
    final bitInvalid = (_invalid >> index).isOdd;
    return _bitsToLogicValue(bitValue, bitInvalid);
  }

  @override
  LogicValue _getRange(int start, int end) {
    final newWidth = end - start;
    if (newWidth > LogicValue._INT_BITS) {
      return LogicValue._bigLogicValueOrFilled(
          (_value >> start) & _maskOfWidth(newWidth),
          (_invalid >> start) & _maskOfWidth(newWidth),
          newWidth);
    } else {
      return LogicValue._smallLogicValueOrFilled(
          ((_value >> start) & _maskOfWidth(newWidth)).toIntUnsigned(newWidth),
          ((_invalid >> start) & _maskOfWidth(newWidth))
              .toIntUnsigned(newWidth),
          newWidth);
    }
  }

  @override
  LogicValue get reversed => LogicValue.of(toList().reversed);

  @override
  bool get isValid => _invalid.sign == 0;

  @override
  bool get isFloating => (_invalid == _mask) && (_value == BigInt.one);

  @override
  BigInt toBigInt() {
    if (_invalid.sign != 0) {
      throw Exception('Cannot convert invalid LogicValue to BigInt: $this');
    }
    return _value;
  }

  @override
  int toInt() =>
      throw Exception('LogicValue width $width is too long to convert to int.'
          ' Use toBigInt() instead.');

  @override
  LogicValue operator ~() => LogicValue._bigLogicValueOrFilled(
      ~_value & ~_invalid & _mask, _invalid, width);

  @override
  LogicValue _and2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    final eitherInvalid = _invalid | other._invalid;
    final eitherZero =
        (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return LogicValue._bigLogicValueOrFilled(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, width);
  }

  @override
  LogicValue _or2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    final eitherInvalid = _invalid | other._invalid;
    final eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return LogicValue._bigLogicValueOrFilled(
        eitherOne, eitherInvalid & ~eitherOne, width);
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    final eitherInvalid = _invalid | other._invalid;
    return LogicValue._bigLogicValueOrFilled(
        (_value ^ other._value) & ~eitherInvalid, eitherInvalid, width);
  }

  @override
  LogicValue and() => (~_value & ~_invalid) & _mask != BigInt.zero
      ? LogicValue.zero
      : !isValid
          ? LogicValue.x
          : LogicValue.one;

  @override
  LogicValue or() => (_value ^ _invalid) & _value != BigInt.zero
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
    while (shiftedValue != BigInt.zero) {
      result ^= shiftedValue.isOdd ? 1 : 0;
      shiftedValue >>= 1;
    }
    return result == 0 ? LogicValue.zero : LogicValue.one;
  }

  @override
  LogicValue _shiftLeft(int shamt) => !isValid
      ? _FilledLogicValue(_LogicValueEnum.x, width)
      : LogicValue._bigLogicValueOrFilled(
          (_value << shamt) & _mask, (_invalid << shamt) & _mask, width);

  @override
  LogicValue _shiftRight(int shamt) => !isValid
      ? _FilledLogicValue(_LogicValueEnum.x, width)
      : LogicValue._bigLogicValueOrFilled(
          _value >> shamt, _invalid >> shamt, width);

  @override
  LogicValue _shiftArithmeticRight(int shamt) => !isValid
      ? _FilledLogicValue(_LogicValueEnum.x, width)
      : LogicValue._bigLogicValueOrFilled(
          (_value |
                  (this[width - 1] == LogicValue.one
                      ? ((_mask >> (width - shamt)) << (width - shamt))
                      : BigInt.zero)) >>
              shamt,
          _invalid >> shamt,
          width);

  @override
  BigInt get _bigIntInvalid => _invalid;

  @override
  BigInt get _bigIntValue => _value;

  @override
  int get _intInvalid => _invalid.toIntUnsigned(width);

  @override
  int get _intValue => _value.toIntUnsigned(width);
}
