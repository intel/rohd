/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// small_logic_values.dart
/// Definition for a logical value where the width is less
/// than or equal to the size of an int.
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

part of values;

/// A [LogicValue] whose number of bits is less than or equal to the size of an int.
///
/// The implementation uses two ints to represent the 4-value value.  Each 0 and 1 bit in [_value]
/// represents a 0 or 1, respectively, if the corresponding bit in [_invalid] is 0; otherwise, each
/// 0 and 1 bit in [_value] represents a x or z, respectively.
///
/// | [_value]  | [_invalid] | 4-value |
/// |-----------|------------|---------|
/// | 0         | 0          | 0       |
/// | 1         | 0          | 1       |
/// | 0         | 1          | x       |
/// | 1         | 1          | z       |
///
class _SmallLogicValues extends LogicValue {
  // Each 0/1 bit in value is 0/1 if !invalid, else is x/z

  final int _value;
  final int _invalid;

  int get _mask => _maskOfWidth(width);
  static final Map<int, int> _masksOfWidth = {};
  static int _maskOfWidth(int width) {
    if (!_masksOfWidth.containsKey(width)) {
      _masksOfWidth[width] = (1 << width) - 1;
    }
    return _masksOfWidth[width]!;
  }

  const _SmallLogicValues(int value, int invalid, int width)
      : assert(width <= LogicValue._INT_BITS),
        _value = ((1 << width) - 1) & value,
        _invalid = ((1 << width) - 1) & invalid,
        super._(width);

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValues) return other == this;
    if (other is! _SmallLogicValues) return false;
    return _value == other._value && _invalid == other._invalid;
  }

  @override
  int get _hashCode => _value.hashCode ^ _invalid.hashCode;

  @override
  LogicValue _getIndex(int index) {
    var bitValue = ((_value >> index) & 1) == 1;
    var bitInvalid = ((_invalid >> index) & 1) == 1;
    return _bitsToLogicValue(bitValue, bitInvalid);
  }

  @override
  LogicValue _getRange(int start, int end) {
    var newWidth = end - start;
    return _SmallLogicValues((_value >> start) & _maskOfWidth(newWidth),
        (_invalid >> start) & _maskOfWidth(newWidth), newWidth);
  }

  @override
  LogicValue get reversed => LogicValue.of(toList().reversed);

  @override
  bool get isValid => _invalid == 0;

  @override
  bool get isFloating => (_invalid == _mask) && (_value == _mask);

  @override
  BigInt toBigInt() => BigInt.from(toInt());

  @override
  int toInt() {
    if (_invalid != 0) {
      throw Exception('Cannot convert invalid LogicValues to int: $this');
    }
    return _value;
  }

  @override
  LogicValue operator ~() =>
      _SmallLogicValues(~_value & ~_invalid & _mask, _invalid, width);

  @override
  LogicValue _and2(LogicValue other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherZero = (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return _SmallLogicValues(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, width);
  }

  @override
  LogicValue _or2(LogicValue other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return _SmallLogicValues(eitherOne, eitherInvalid & ~eitherOne, width);
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    return _SmallLogicValues(
        (_value ^ other._value) & ~eitherInvalid, eitherInvalid, width);
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
    if (!isValid) return LogicValue.x;
    var shiftedValue = _value;
    var result = 0;
    while (shiftedValue != 0) {
      result ^= shiftedValue & 1;
      shiftedValue >>= 1;
    }
    return result == 0 ? LogicValue.zero : LogicValue.one;
  }

  @override
  LogicValue _shiftLeft(int shamt) => !isValid
      ? _FilledLogicValues(_LogicValueEnum.x, width)
      : _SmallLogicValues(
          (_value << shamt) & _mask, (_invalid << shamt) & _mask, width);

  @override
  LogicValue _shiftRight(int shamt) => !isValid
      ? _FilledLogicValues(_LogicValueEnum.x, width)
      : _SmallLogicValues(_value >> shamt, _invalid >> shamt, width);

  @override
  LogicValue _shiftArithmeticRight(int shamt) => !isValid
      ? _FilledLogicValues(_LogicValueEnum.x, width)
      : _SmallLogicValues(
          ((_value | (this[width - 1] == LogicValue.one ? ~_mask : 0)) >>
                  shamt) &
              _mask,
          _invalid >> shamt,
          width);
}
