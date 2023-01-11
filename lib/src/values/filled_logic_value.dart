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

  const _FilledLogicValue(_LogicValueEnum value, super.width)
      : _value = width > 0 ? value : _LogicValueEnum.zero,
        assert(width >= 0, 'Must be non-negative width'),
        super._();

  @override
  bool _equals(Object other) {
    if (other is! LogicValue) {
      return false;
    }

    if (other.width != width) {
      return false;
    }

    if (other.width == 0 && width == 0) {
      return true;
    }

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
    throw Exception('Unexpected unknown comparison between $runtimeType'
        ' and ${other.runtimeType}.');
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
      throw Exception('LogicValue width $width is too long to convert to int.'
          ' Use toBigInt() instead.');
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

  /// Constructs a [_SmallLogicValue] based on [value] and [invalid],
  /// and bypasses assertions for inefficient representations.
  _SmallLogicValue _buildSmallLogicValue(bool value, bool invalid) =>
      _SmallLogicValue(
        value ? _SmallLogicValue._maskOfWidth(width) : 0,
        invalid ? _SmallLogicValue._maskOfWidth(width) : 0,
        width,
        allowInefficientRepresentation: true,
      );

  /// Converts this to a [_SmallLogicValue] representation.
  ///
  /// This should only be used for temporary calculations.
  _SmallLogicValue _toSmallLogicValue() {
    switch (_value) {
      case _LogicValueEnum.x:
        return _buildSmallLogicValue(false, true);
      case _LogicValueEnum.z:
        return _buildSmallLogicValue(true, true);
      case _LogicValueEnum.one:
        return _buildSmallLogicValue(true, false);
      case _LogicValueEnum.zero:
        return _buildSmallLogicValue(false, false);
    }
  }

  /// Constructs a [_BigLogicValue] based on [value] and [invalid],
  /// and bypasses assertions for inefficient representations.
  _BigLogicValue _buildBigLogicValue(bool value, bool invalid) =>
      _BigLogicValue(
        value ? _BigLogicValue._maskOfWidth(width) : BigInt.zero,
        invalid ? _BigLogicValue._maskOfWidth(width) : BigInt.zero,
        width,
        allowInefficientRepresentation: true,
      );

  /// Converts this to a [_BigLogicValue] representation.
  ///
  /// This should only be used for temporary calculations.
  _BigLogicValue _toBigLogicValue() {
    switch (_value) {
      case _LogicValueEnum.x:
        return _buildBigLogicValue(false, true);
      case _LogicValueEnum.z:
        return _buildBigLogicValue(true, true);
      case _LogicValueEnum.one:
        return _buildBigLogicValue(true, false);
      case _LogicValueEnum.zero:
        return _buildBigLogicValue(false, false);
    }
  }

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
      return LogicValue._smallLogicValueOrFilled(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValue) {
      // _value is 1
      return LogicValue._bigLogicValueOrFilled(
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
      return LogicValue._smallLogicValueOrFilled(
          other._value & ~other._invalid, other._invalid, width);
    } else if (other is _BigLogicValue) {
      // _value is 0
      return LogicValue._bigLogicValueOrFilled(
          other._value & ~other._invalid, other._invalid, width);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue _xor2(LogicValue other) {
    if (other is _FilledLogicValue) {
      if (!isValid || !other.isValid) {
        return LogicValue.x;
      }
      return ((_value == _LogicValueEnum.one) ^
              (other._value == _LogicValueEnum.one))
          ? _FilledLogicValue(_LogicValueEnum.one, width)
          : _FilledLogicValue(_LogicValueEnum.zero, width);
    } else if (!isValid) {
      return _FilledLogicValue(_LogicValueEnum.x, width);
    } else if (_value == _LogicValueEnum.zero) {
      if (other is _SmallLogicValue) {
        return LogicValue._smallLogicValueOrFilled(
            other._value & ~other._invalid, other._invalid, width);
      } else if (other is _BigLogicValue) {
        return LogicValue._bigLogicValueOrFilled(
            other._value & ~other._invalid, other._invalid, width);
      }
    } else if (_value == _LogicValueEnum.one) {
      if (other is _SmallLogicValue) {
        return LogicValue._smallLogicValueOrFilled(
            ~other._value & other._mask & ~other._invalid,
            other._invalid,
            width);
      } else if (other is _BigLogicValue) {
        return LogicValue._bigLogicValueOrFilled(
            ~other._value & other._mask & ~other._invalid,
            other._invalid,
            width);
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
  LogicValue _shiftLeft(int shamt) {
    if (_value == _LogicValueEnum.zero) {
      return this;
    }

    if (shamt >= width) {
      return _FilledLogicValue(_LogicValueEnum.zero, width);
    }

    return [
      getRange(0, width - shamt),
      _FilledLogicValue(_LogicValueEnum.zero, shamt),
    ].swizzle();
  }

  @override
  LogicValue _shiftRight(int shamt) {
    if (_value == _LogicValueEnum.zero) {
      return this;
    }

    if (shamt >= width) {
      return _FilledLogicValue(_LogicValueEnum.zero, width);
    }

    return [
      _FilledLogicValue(_LogicValueEnum.zero, shamt),
      getRange(shamt, width),
    ].swizzle();
  }

  @override
  LogicValue _shiftArithmeticRight(int shamt) => this;

  @override
  BigInt get _bigIntInvalid =>
      (_value == _LogicValueEnum.z || _value == _LogicValueEnum.x)
          ? _BigLogicValue._maskOfWidth(width)
          : BigInt.zero;

  @override
  BigInt get _bigIntValue =>
      (_value == _LogicValueEnum.one || _value == _LogicValueEnum.z)
          ? _BigLogicValue._maskOfWidth(width)
          : BigInt.zero;

  @override
  int get _intInvalid =>
      (_value == _LogicValueEnum.z || _value == _LogicValueEnum.x)
          ? _SmallLogicValue._maskOfWidth(width)
          : 0;

  @override
  int get _intValue =>
      (_value == _LogicValueEnum.one || _value == _LogicValueEnum.z)
          ? _SmallLogicValue._maskOfWidth(width)
          : 0;
}
