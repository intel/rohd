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

/// A [LogicValue] whose number of bits is greater than the size of an [int].
///
/// The implementation is similar to [_SmallLogicValue], except it uses [BigInt].
///
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

  _BigLogicValue(BigInt value, BigInt invalid, int width)
      : assert(width > LogicValue._INT_BITS),
        super._(width) {
    _value = _mask & value;
    _invalid = _mask & invalid;
  }

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValue) return other == this;
    if (other is! _BigLogicValue) return false;
    return _value == other._value && _invalid == other._invalid;
  }

  @override
  int get _hashCode => _value.hashCode ^ _invalid.hashCode;

  @override
  LogicValue _getIndex(int index) {
    var bitValue = (_value >> index).isOdd;
    var bitInvalid = (_invalid >> index).isOdd;
    return _bitsToLogicValue(bitValue, bitInvalid);
  }

  @override
  LogicValue _getRange(int start, int end) {
    var newWidth = end - start;
    if (newWidth > LogicValue._INT_BITS) {
      return _BigLogicValue((_value >> start) & _maskOfWidth(newWidth),
          (_invalid >> start) & _maskOfWidth(newWidth), newWidth);
    } else {
      return _SmallLogicValue(
          ((_value >> start) & _maskOfWidth(newWidth)).toInt(),
          ((_invalid >> start) & _maskOfWidth(newWidth)).toInt(),
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
      throw Exception('Cannot convert invalid LogicValue to BigInt: ${this}');
    }
    return _value;
  }

  @override
  int toInt() => throw Exception(
      'LogicValue width $width is too long to convert to int. Use toBigInt() instead.');

  @override
  LogicValue operator ~() =>
      _BigLogicValue(~_value & ~_invalid & _mask, _invalid, width);

  @override
  LogicValue _and2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherZero = (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return _BigLogicValue(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, width);
  }

  @override
  LogicValue _or2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return _BigLogicValue(eitherOne, eitherInvalid & ~eitherOne, width);
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is! _BigLogicValue) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    return _BigLogicValue(
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
    if (!isValid) return LogicValue.x;
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
      : _BigLogicValue(
          (_value << shamt) & _mask, (_invalid << shamt) & _mask, width);

  @override
  LogicValue _shiftRight(int shamt) => !isValid
      ? _FilledLogicValue(_LogicValueEnum.x, width)
      : _BigLogicValue(_value >> shamt, _invalid >> shamt, width);

  @override
  LogicValue _shiftArithmeticRight(int shamt) => !isValid
      ? _FilledLogicValue(_LogicValueEnum.x, width)
      : _BigLogicValue(
          ((_value |
                  (this[width - 1] == LogicValue.one
                      ? ((_mask >> (width - shamt)) << (width - shamt))
                      : BigInt.zero)) >>
              shamt),
          _invalid >> shamt,
          width);
}
