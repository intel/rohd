/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// filled_logic_value.dart
/// Definition for a logical value where all bits are the same value.
///
/// 2022 March 28
/// Author: Max Korbel <max.korbel@intel.com>
///

part of values;

/// A [LogicValue] of any width where all bits are the same [LogicValue].
class _FilledLogicValue extends LogicValue {
  final _LogicValueEnum _value;

  const _FilledLogicValue(this._value, int width) : super._(width);

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValue) {
      return _value == other._value;
    } else if (other is _SmallLogicValue) {
      if (_value == _LogicValueEnum.zero) {
        return other._value == 0 && other._invalid == 0;
      } else if (_value == _LogicValueEnum.one) {
        return other._value == other._mask && other._invalid == 0;
      } else if (_value == _LogicValueEnum.x) {
        return other._value == 0 && other._invalid == other._mask;
      } else if (_value == _LogicValueEnum.z) {
        return other._value == other._mask && other._invalid == other._mask;
      }
    } else if (other is _BigLogicValue) {
      if (_value == _LogicValueEnum.zero) {
        return other._value.sign == 0 && other._invalid.sign == 0;
      } else if (_value == _LogicValueEnum.one) {
        return other._value == other._mask && other._invalid.sign == 0;
      } else if (_value == _LogicValueEnum.x) {
        return other._value.sign == 0 && other._invalid == other._mask;
      } else if (_value == _LogicValueEnum.z) {
        return other._value == other._mask && other._invalid == other._mask;
      }
    }
    throw Exception(
        'Unexpected unknown comparison between $runtimeType and ${other.runtimeType}.');
  }

  @override
  LogicValue _getIndex(int index) => _FilledLogicValue(_value, 1);

  @override
  LogicValue _getRange(int start, int end) =>
      _FilledLogicValue(_value, end - start);

  @override
  LogicValue get reversed => this;

  @override
  int get _hashCode => _value.hashCode;

  @override
  bool get isValid =>
      !(_value == _LogicValueEnum.x || _value == _LogicValueEnum.z);

  @override
  bool get isFloating => _value == _LogicValueEnum.z;

  @override
  BigInt toBigInt() {
    if (_value == _LogicValueEnum.one) {
      return _BigLogicValue._maskOfWidth(width);
    } else if (_value == _LogicValueEnum.zero) {
      return BigInt.zero;
    }
    throw Exception('Cannot convert invalid value "$_value" to BigInt.');
  }

  @override
  int toInt() {
    if (width > LogicValue._INT_BITS) {
      throw Exception(
          'LogicValue width $width is too long to convert to int. Use toBigInt() instead.');
    }
    if (_value == _LogicValueEnum.one) {
      return _SmallLogicValue._maskOfWidth(width);
    } else if (_value == _LogicValueEnum.zero) {
      return 0;
    }
    throw Exception('Cannot convert invalid value "$_value" to an int.');
  }

  @override
  LogicValue operator ~() => _FilledLogicValue(
      !isValid
          ? _LogicValueEnum.x
          : _value == _LogicValueEnum.zero
              ? _LogicValueEnum.one
              : _LogicValueEnum.zero,
      width);

  _SmallLogicValue _toSmallLogicValue() => _value == _LogicValueEnum.x
      ? _SmallLogicValue(0, _SmallLogicValue._maskOfWidth(width), width)
      : _value == _LogicValueEnum.z
          ? _SmallLogicValue(_SmallLogicValue._maskOfWidth(width),
              _SmallLogicValue._maskOfWidth(width), width)
          : _value == _LogicValueEnum.one
              ? _SmallLogicValue(_SmallLogicValue._maskOfWidth(width), 0, width)
              : _SmallLogicValue(0, 0, width);

  _BigLogicValue _toBigLogicValue() => _value == _LogicValueEnum.x
      ? _BigLogicValue(BigInt.zero, _BigLogicValue._maskOfWidth(width), width)
      : _value == _LogicValueEnum.z
          ? _BigLogicValue(_BigLogicValue._maskOfWidth(width),
              _BigLogicValue._maskOfWidth(width), width)
          : _value == _LogicValueEnum.one
              ? _BigLogicValue(
                  _BigLogicValue._maskOfWidth(width), BigInt.zero, width)
              : _BigLogicValue(BigInt.zero, BigInt.zero, width);

  @override
  LogicValue _and2(LogicValue other) {
    if (other is _FilledLogicValue) {
      if (_value == _LogicValueEnum.zero ||
          other._value == _LogicValueEnum.zero) {
        return _FilledLogicValue(_LogicValueEnum.zero, width);
      }
      if (!isValid || !other.isValid) {
        return _FilledLogicValue(_LogicValueEnum.x, width);
      }
      return (_value == _LogicValueEnum.one &&
              other._value == _LogicValueEnum.one)
          ? _FilledLogicValue(_LogicValueEnum.one, width)
          : _FilledLogicValue(_LogicValueEnum.zero, width);
    } else if (_value == _LogicValueEnum.zero) {
      return _FilledLogicValue(_LogicValueEnum.zero, width);
    } else if (!isValid) {
      if (other is _SmallLogicValue) {
        return other & _toSmallLogicValue();
      } else if (other is _BigLogicValue) {
        return other & _toBigLogicValue();
      }
    } else if (other is _SmallLogicValue) {
      // _value is 1
      return _SmallLogicValue(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValue) {
      // _value is 1
      return _BigLogicValue(
          other._value & ~other._invalid, other._invalid, width);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue _or2(LogicValue other) {
    if (other is _FilledLogicValue) {
      return (_value == _LogicValueEnum.one ||
              other._value == _LogicValueEnum.one)
          ? _FilledLogicValue(_LogicValueEnum.one, width)
          : (isValid && other.isValid)
              ? _FilledLogicValue(_LogicValueEnum.zero, width)
              : _FilledLogicValue(_LogicValueEnum.x, width);
    } else if (_value == _LogicValueEnum.one) {
      return _FilledLogicValue(_LogicValueEnum.one, width);
    } else if (!isValid) {
      if (other is _SmallLogicValue) {
        return other | _toSmallLogicValue();
      } else if (other is _BigLogicValue) {
        return other | _toBigLogicValue();
      }
      return _FilledLogicValue(_LogicValueEnum.x, width);
    } else if (other is _SmallLogicValue) {
      // _value is 0
      return _SmallLogicValue(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValue) {
      // _value is 0
      return _BigLogicValue(
          other._value & ~other._invalid, other._invalid, width);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is _FilledLogicValue) {
      if (!isValid || !other.isValid) return LogicValue.x;
      return ((_value == _LogicValueEnum.one) ^
              (other._value == _LogicValueEnum.one))
          ? _FilledLogicValue(_LogicValueEnum.one, width)
          : _FilledLogicValue(_LogicValueEnum.zero, width);
    } else if (!isValid) {
      return _FilledLogicValue(_LogicValueEnum.x, width);
    } else if (_value == _LogicValueEnum.zero) {
      if (other is _SmallLogicValue) {
        return _SmallLogicValue(
            other._value & ~other._invalid, other._invalid, width);
      } else if (other is _BigLogicValue) {
        return _BigLogicValue(
            other._value & ~other._invalid, other._invalid, width);
      }
    } else if (_value == _LogicValueEnum.one) {
      if (other is _SmallLogicValue) {
        return _SmallLogicValue(~other._value & other._mask & ~other._invalid,
            other._invalid, width);
      } else if (other is _BigLogicValue) {
        return _BigLogicValue(~other._value & other._mask & ~other._invalid,
            other._invalid, width);
      }
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue and() => !isValid
      ? LogicValue.x
      : _value == _LogicValueEnum.one
          ? LogicValue.one
          : LogicValue.zero;

  @override
  LogicValue or() => and();

  @override
  LogicValue xor() => !isValid
      ? LogicValue.x
      : _value == _LogicValueEnum.zero
          ? LogicValue.zero
          : width.isOdd
              ? LogicValue.one
              : LogicValue.zero;

  @override
  LogicValue _shiftLeft(int shamt) => LogicValue.ofString(
      (this[0]._bitString() * (width - shamt)) + ('0' * shamt));

  @override
  LogicValue _shiftRight(int shamt) => LogicValue.ofString(
      ('0' * shamt) + (this[0]._bitString() * (width - shamt)));

  @override
  LogicValue _shiftArithmeticRight(int shamt) => LogicValue.ofString(
      ((_value == _LogicValueEnum.one ? '1' : '0') * shamt) +
          (this[0]._bitString() * (width - shamt)));
}
