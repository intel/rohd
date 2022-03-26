/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// filled_logic_values.dart
/// Definition for a logical value where all bits are the same value.
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

part of values;

/// A [LogicValue] of any width where all bits are the same [LogicValue].
class _FilledLogicValues extends LogicValue {
  final _LogicValueEnum _value;

  const _FilledLogicValues(this._value, int width) : super._(width);

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValues) {
      return _value == other._value;
    } else if (other is _SmallLogicValues) {
      if (_value == _LogicValueEnum.zero) {
        return other._value == 0 && other._invalid == 0;
      } else if (_value == _LogicValueEnum.one) {
        return other._value == other._mask && other._invalid == 0;
      } else if (_value == _LogicValueEnum.x) {
        return other._value == 0 && other._invalid == other._mask;
      } else if (_value == _LogicValueEnum.z) {
        return other._value == other._mask && other._invalid == other._mask;
      }
    } else if (other is _BigLogicValues) {
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
  LogicValue _getIndex(int index) => _FilledLogicValues(_value, 1);

  @override
  LogicValue _getRange(int start, int end) =>
      _FilledLogicValues(_value, end - start);

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
      return _BigLogicValues._maskOfWidth(width);
    } else if (_value == _LogicValueEnum.zero) {
      return BigInt.zero;
    }
    throw Exception('Cannot convert invalid value "$_value" to an int.');
  }

  @override
  int toInt() {
    if (width > LogicValue._INT_BITS) {
      throw Exception(
          'LogicValues width $width is too long to convert to int. Use toBigInt() instead.');
    }
    if (_value == _LogicValueEnum.one) {
      return _SmallLogicValues._maskOfWidth(width);
    } else if (_value == _LogicValueEnum.zero) {
      return 0;
    }
    throw Exception('Cannot convert invalid value "$_value" to an int.');
  }

  @override
  LogicValue operator ~() => _FilledLogicValues(
      !isValid
          ? _LogicValueEnum.x
          : _value == _LogicValueEnum.zero
              ? _LogicValueEnum.one
              : _LogicValueEnum.zero,
      width);

  _SmallLogicValues _toSmallLogicValues() => _value == _LogicValueEnum.x
      ? _SmallLogicValues(0, _SmallLogicValues._maskOfWidth(width), width)
      : _value == _LogicValueEnum.z
          ? _SmallLogicValues(_SmallLogicValues._maskOfWidth(width),
              _SmallLogicValues._maskOfWidth(width), width)
          : _value == _LogicValueEnum.one
              ? _SmallLogicValues(
                  _SmallLogicValues._maskOfWidth(width), 0, width)
              : _SmallLogicValues(0, 0, width);

  _BigLogicValues _toBigLogicValues() => _value == _LogicValueEnum.x
      ? _BigLogicValues(BigInt.zero, _BigLogicValues._maskOfWidth(width), width)
      : _value == _LogicValueEnum.z
          ? _BigLogicValues(_BigLogicValues._maskOfWidth(width),
              _BigLogicValues._maskOfWidth(width), width)
          : _value == _LogicValueEnum.one
              ? _BigLogicValues(
                  _BigLogicValues._maskOfWidth(width), BigInt.zero, width)
              : _BigLogicValues(BigInt.zero, BigInt.zero, width);

  @override
  LogicValue _and2(LogicValue other) {
    if (other is _FilledLogicValues) {
      if (_value == _LogicValueEnum.zero ||
          other._value == _LogicValueEnum.zero) {
        return _FilledLogicValues(_LogicValueEnum.zero, width);
      }
      if (!isValid || !other.isValid) {
        return _FilledLogicValues(_LogicValueEnum.x, width);
      }
      return (_value == _LogicValueEnum.one &&
              other._value == _LogicValueEnum.one)
          ? _FilledLogicValues(_LogicValueEnum.one, width)
          : _FilledLogicValues(_LogicValueEnum.zero, width);
    } else if (_value == _LogicValueEnum.zero) {
      return _FilledLogicValues(_LogicValueEnum.zero, width);
    } else if (!isValid) {
      if (other is _SmallLogicValues) {
        return other & _toSmallLogicValues();
      } else if (other is _BigLogicValues) {
        return other & _toBigLogicValues();
      }
    } else if (other is _SmallLogicValues) {
      // _value is 1
      return _SmallLogicValues(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValues) {
      // _value is 1
      return _BigLogicValues(
          other._value & ~other._invalid, other._invalid, width);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue _or2(LogicValue other) {
    if (other is _FilledLogicValues) {
      return (_value == _LogicValueEnum.one ||
              other._value == _LogicValueEnum.one)
          ? _FilledLogicValues(_LogicValueEnum.one, width)
          : (isValid && other.isValid)
              ? _FilledLogicValues(_LogicValueEnum.zero, width)
              : _FilledLogicValues(_LogicValueEnum.x, width);
    } else if (_value == _LogicValueEnum.one) {
      return _FilledLogicValues(_LogicValueEnum.one, width);
    } else if (!isValid) {
      if (other is _SmallLogicValues) {
        return other | _toSmallLogicValues();
      } else if (other is _BigLogicValues) {
        return other | _toBigLogicValues();
      }
      return _FilledLogicValues(_LogicValueEnum.x, width);
    } else if (other is _SmallLogicValues) {
      // _value is 0
      return _SmallLogicValues(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValues) {
      // _value is 0
      return _BigLogicValues(
          other._value & ~other._invalid, other._invalid, width);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is _FilledLogicValues) {
      if (!isValid || !other.isValid) return LogicValue.x;
      return ((_value == _LogicValueEnum.one) ^
              (other._value == _LogicValueEnum.one))
          ? _FilledLogicValues(_LogicValueEnum.one, width)
          : _FilledLogicValues(_LogicValueEnum.zero, width);
    } else if (!isValid) {
      return _FilledLogicValues(_LogicValueEnum.x, width);
    } else if (_value == _LogicValueEnum.zero) {
      if (other is _SmallLogicValues) {
        return _SmallLogicValues(
            other._value & ~other._invalid, other._invalid, width);
      } else if (other is _BigLogicValues) {
        return _BigLogicValues(
            other._value & ~other._invalid, other._invalid, width);
      }
    } else if (_value == _LogicValueEnum.one) {
      if (other is _SmallLogicValues) {
        return _SmallLogicValues(~other._value & other._mask & ~other._invalid,
            other._invalid, width);
      } else if (other is _BigLogicValues) {
        return _BigLogicValues(~other._value & other._mask & ~other._invalid,
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
  LogicValue _shiftLeft(int shamt) =>
      LogicValue.ofString(_value.toString() * (width - shamt) + '0' * shamt);

  @override
  LogicValue _shiftRight(int shamt) =>
      LogicValue.ofString('0' * shamt + _value.toString() * (width - shamt));

  @override
  LogicValue _shiftArithmeticRight(int shamt) =>
      LogicValue.ofString((_value == _LogicValueEnum.one ? '1' : '0') * shamt +
          _value.toString() * (width - shamt));
}
