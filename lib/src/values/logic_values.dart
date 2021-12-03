/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_values.dart
/// Definitions for a set of logical values of any length
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// A [LogicValues] whose number of bits is less than or equal to the size of an int.
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
class _SmallLogicValues extends LogicValues {
  // Each 0/1 bit in value is 0/1 if !invalid, else is x/z

  final int _value;
  final int _invalid;

  int get _mask => _maskOfLength(length);
  static final Map<int, int> _masksOfLength = {};
  static int _maskOfLength(int length) {
    if (!_masksOfLength.containsKey(length)) {
      _masksOfLength[length] = (1 << length) - 1;
    }
    return _masksOfLength[length]!;
  }

  const _SmallLogicValues(int value, int invalid, int length)
      : assert(length <= LogicValues._INT_BITS),
        _value = ((1 << length) - 1) & value,
        _invalid = ((1 << length) - 1) & invalid,
        super._(length);

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
  LogicValues _getRange(int start, int end) {
    var newLength = end - start;
    return _SmallLogicValues((_value >> start) & _maskOfLength(newLength),
        (_invalid >> start) & _maskOfLength(newLength), newLength);
  }

  @override
  LogicValues get reversed => LogicValues.from(toList().reversed);

  @override
  bool get isValid => _invalid == 0;

  @override
  bool get isFloating => (_invalid == _mask) && (_value == _mask);

  @override
  BigInt toBigInt() => BigInt.from(toInt());

  @override
  int toInt() {
    if (_invalid != 0) {
      throw Exception('Cannot convert invalid LogicValues to int: ${this}');
    }
    return _value;
  }

  @override
  LogicValues operator ~() =>
      _SmallLogicValues(~_value & ~_invalid & _mask, _invalid, length);

  @override
  LogicValues _and2(LogicValues other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherZero = (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return _SmallLogicValues(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, length);
  }

  @override
  LogicValues _or2(LogicValues other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return _SmallLogicValues(eitherOne, eitherInvalid & ~eitherOne, length);
  }

  @override
  LogicValues _xor2(LogicValues other) {
    if (other is! _SmallLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    return _SmallLogicValues(
        (_value ^ other._value) & ~eitherInvalid, eitherInvalid, length);
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
  LogicValues _shiftLeft(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _SmallLogicValues(
          (_value << shamt) & _mask, (_invalid << shamt) & _mask, length);

  @override
  LogicValues _shiftRight(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _SmallLogicValues(_value >> shamt, _invalid >> shamt, length);

  @override
  LogicValues _shiftArithmeticRight(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _SmallLogicValues(
          ((_value | (this[length - 1] == LogicValue.one ? ~_mask : 0)) >>
                  shamt) &
              _mask,
          _invalid >> shamt,
          length);
}

/// A [LogicValues] whose number of bits is greater than the size of an [int].
///
/// The implementation is similar to [_SmallLogicValues], except it uses [BigInt].
///
class _BigLogicValues extends LogicValues {
  late final BigInt _value;
  late final BigInt _invalid;

  BigInt get _mask => _maskOfLength(length);
  static final Map<int, BigInt> _masksOfLength = {};
  static BigInt _maskOfLength(int length) {
    if (!_masksOfLength.containsKey(length)) {
      _masksOfLength[length] = (BigInt.one << length) - BigInt.one;
    }
    return _masksOfLength[length]!;
  }

  _BigLogicValues(BigInt value, BigInt invalid, int length)
      : assert(length > LogicValues._INT_BITS),
        super._(length) {
    _value = _mask & value;
    _invalid = _mask & invalid;
  }

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValues) return other == this;
    if (other is! _BigLogicValues) return false;
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
  LogicValues _getRange(int start, int end) {
    var newLength = end - start;
    if (newLength > LogicValues._INT_BITS) {
      return _BigLogicValues((_value >> start) & _maskOfLength(newLength),
          (_invalid >> start) & _maskOfLength(newLength), newLength);
    } else {
      return _SmallLogicValues(
          ((_value >> start) & _maskOfLength(newLength)).toInt(),
          ((_invalid >> start) & _maskOfLength(newLength)).toInt(),
          newLength);
    }
  }

  @override
  LogicValues get reversed => LogicValues.from(toList().reversed);

  @override
  bool get isValid => _invalid.sign == 0;

  @override
  bool get isFloating => (_invalid == _mask) && (_value == BigInt.one);

  @override
  BigInt toBigInt() {
    if (_invalid.sign != 0) {
      throw Exception('Cannot convert invalid LogicValues to int: ${this}');
    }
    return _value;
  }

  @override
  int toInt() => throw Exception(
      'LogicValues length $length is too long to convert to int. Use toBigInt() instead.');

  @override
  LogicValues operator ~() =>
      _BigLogicValues(~_value & ~_invalid & _mask, _invalid, length);

  @override
  LogicValues _and2(LogicValues other) {
    if (other is! _BigLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherZero = (~_value & ~_invalid) | (~other._value & ~other._invalid);
    return _BigLogicValues(
        ~eitherInvalid & ~eitherZero, eitherInvalid & ~eitherZero, length);
  }

  @override
  LogicValues _or2(LogicValues other) {
    if (other is! _BigLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    var eitherOne = (_value & ~_invalid) | (other._value & ~other._invalid);
    return _BigLogicValues(eitherOne, eitherInvalid & ~eitherOne, length);
  }

  @override
  LogicValues _xor2(LogicValues other) {
    if (other is! _BigLogicValues) {
      throw Exception('Cannot handle type ${other.runtimeType} here.');
    }
    var eitherInvalid = _invalid | other._invalid;
    return _BigLogicValues(
        (_value ^ other._value) & ~eitherInvalid, eitherInvalid, length);
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
  LogicValues _shiftLeft(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _BigLogicValues(
          (_value << shamt) & _mask, (_invalid << shamt) & _mask, length);

  @override
  LogicValues _shiftRight(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _BigLogicValues(_value >> shamt, _invalid >> shamt, length);

  @override
  LogicValues _shiftArithmeticRight(int shamt) => !isValid
      ? _FilledLogicValues(LogicValue.x, length)
      : _BigLogicValues(
          ((_value |
                  (this[length - 1] == LogicValue.one
                      ? ((_mask >> (length - shamt)) << (length - shamt))
                      : BigInt.zero)) >>
              shamt),
          _invalid >> shamt,
          length);
}

/// A [LogicValues] of any length where all bits are the same [LogicValue].
class _FilledLogicValues extends LogicValues {
  final LogicValue _value;

  const _FilledLogicValues(this._value, int length) : super._(length);

  @override
  bool _equals(Object other) {
    if (other is _FilledLogicValues) {
      return _value == other._value;
    } else if (other is _SmallLogicValues) {
      if (_value == LogicValue.zero) {
        return other._value == 0 && other._invalid == 0;
      } else if (_value == LogicValue.one) {
        return other._value == other._mask && other._invalid == 0;
      } else if (_value == LogicValue.x) {
        return other._value == 0 && other._invalid == other._mask;
      } else if (_value == LogicValue.z) {
        return other._value == other._mask && other._invalid == other._mask;
      }
    } else if (other is _BigLogicValues) {
      if (_value == LogicValue.zero) {
        return other._value.sign == 0 && other._invalid.sign == 0;
      } else if (_value == LogicValue.one) {
        return other._value == other._mask && other._invalid.sign == 0;
      } else if (_value == LogicValue.x) {
        return other._value.sign == 0 && other._invalid == other._mask;
      } else if (_value == LogicValue.z) {
        return other._value == other._mask && other._invalid == other._mask;
      }
    }
    throw Exception('Unexpected unknown comparison.');
  }

  @override
  LogicValue _getIndex(int index) => _value;

  @override
  LogicValues _getRange(int start, int end) =>
      _FilledLogicValues(_value, end - start);

  @override
  LogicValues get reversed => this;

  @override
  int get _hashCode => _value.hashCode;

  @override
  bool get isValid => _value.isValid;

  @override
  bool get isFloating => _value == LogicValue.z;

  @override
  BigInt toBigInt() {
    if (_value == LogicValue.one) {
      return _BigLogicValues._maskOfLength(length);
    } else if (_value == LogicValue.zero) {
      return BigInt.zero;
    }
    throw Exception('Cannot convert invalid value "$_value" to an int.');
  }

  @override
  int toInt() {
    if (length > LogicValues._INT_BITS) {
      throw Exception(
          'LogicValues length $length is too long to convert to int. Use toBigInt() instead.');
    }
    if (_value == LogicValue.one) {
      return _SmallLogicValues._maskOfLength(length);
    } else if (_value == LogicValue.zero) {
      return 0;
    }
    throw Exception('Cannot convert invalid value "$_value" to an int.');
  }

  @override
  LogicValues operator ~() => _FilledLogicValues(~_value, length);

  _SmallLogicValues _toSmallLogicValues() => _value == LogicValue.x
      ? _SmallLogicValues(0, _SmallLogicValues._maskOfLength(length), length)
      : _value == LogicValue.z
          ? _SmallLogicValues(_SmallLogicValues._maskOfLength(length),
              _SmallLogicValues._maskOfLength(length), length)
          : _value == LogicValue.one
              ? _SmallLogicValues(
                  _SmallLogicValues._maskOfLength(length), 0, length)
              : _SmallLogicValues(0, 0, length);

  _BigLogicValues _toBigLogicValues() => _value == LogicValue.x
      ? _BigLogicValues(
          BigInt.zero, _BigLogicValues._maskOfLength(length), length)
      : _value == LogicValue.z
          ? _BigLogicValues(_BigLogicValues._maskOfLength(length),
              _BigLogicValues._maskOfLength(length), length)
          : _value == LogicValue.one
              ? _BigLogicValues(
                  _BigLogicValues._maskOfLength(length), BigInt.zero, length)
              : _BigLogicValues(BigInt.zero, BigInt.zero, length);

  @override
  LogicValues _and2(LogicValues other) {
    if (other is _FilledLogicValues) {
      return _FilledLogicValues(_value & other._value, length);
    } else if (_value == LogicValue.zero) {
      return _FilledLogicValues(LogicValue.zero, length);
    } else if (!isValid) {
      if (other is _SmallLogicValues) {
        return other & _toSmallLogicValues();
      } else if (other is _BigLogicValues) {
        return other & _toBigLogicValues();
      }
    } else if (other is _SmallLogicValues) {
      // _value is 1
      return _SmallLogicValues(
          other._value & ~other._invalid, other._invalid, length);
    } else if (other is _BigLogicValues) {
      // _value is 1
      return _BigLogicValues(
          other._value & ~other._invalid, other._invalid, length);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValues _or2(LogicValues other) {
    if (other is _FilledLogicValues) {
      return _FilledLogicValues(_value | other._value, length);
    } else if (_value == LogicValue.one) {
      return _FilledLogicValues(LogicValue.one, length);
    } else if (!isValid) {
      if (other is _SmallLogicValues) {
        return other | _toSmallLogicValues();
      } else if (other is _BigLogicValues) {
        return other | _toBigLogicValues();
      }
      return _FilledLogicValues(LogicValue.x, length);
    } else if (other is _SmallLogicValues) {
      // _value is 0
      return _SmallLogicValues(
          other._value & ~other._invalid, other._invalid, length);
    } else if (other is _BigLogicValues) {
      // _value is 0
      return _BigLogicValues(
          other._value & ~other._invalid, other._invalid, length);
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValues _xor2(LogicValues other) {
    if (other is _FilledLogicValues) {
      return _FilledLogicValues(_value ^ other._value, length);
    } else if (!isValid) {
      return _FilledLogicValues(LogicValue.x, length);
    } else if (_value == LogicValue.zero) {
      if (other is _SmallLogicValues) {
        return _SmallLogicValues(
            other._value & ~other._invalid, other._invalid, length);
      } else if (other is _BigLogicValues) {
        return _BigLogicValues(
            other._value & ~other._invalid, other._invalid, length);
      }
    } else if (_value == LogicValue.one) {
      if (other is _SmallLogicValues) {
        return _SmallLogicValues(~other._value & other._mask & ~other._invalid,
            other._invalid, length);
      } else if (other is _BigLogicValues) {
        return _BigLogicValues(~other._value & other._mask & ~other._invalid,
            other._invalid, length);
      }
    }
    throw Exception('Unhandled scenario.');
  }

  @override
  LogicValue and() => !isValid
      ? LogicValue.x
      : _value == LogicValue.one
          ? _value
          : LogicValue.zero;

  @override
  LogicValue or() => and();

  @override
  LogicValue xor() => !isValid
      ? LogicValue.x
      : _value == LogicValue.zero
          ? _value
          : length.isOdd
              ? LogicValue.one
              : LogicValue.zero;

  @override
  LogicValues _shiftLeft(int shamt) => LogicValues.fromString(
      _value.toString() * (length - shamt) + '0' * shamt);

  @override
  LogicValues _shiftRight(int shamt) => LogicValues.fromString(
      '0' * shamt + _value.toString() * (length - shamt));

  @override
  LogicValues _shiftArithmeticRight(int shamt) =>
      LogicValues.fromString((_value == LogicValue.one ? '1' : '0') * shamt +
          _value.toString() * (length - shamt));
}

/// An immutable 4-value representation of an arbitrary number of bits.
///
/// Each bit of [LogicValues] can be represented as a [LogicValue] of `0`, `1`, `x` (contention), or `z` (floating).
@Immutable()
abstract class LogicValues {
  /// The number of bits in an int.
  // ignore: constant_identifier_names
  static const int _INT_BITS = 64;

  /// The number of bits in this `LogicValues`.
  final int length;

  const LogicValues._(this.length) : assert(length >= 0);

  /// Converts `int` [value] to a valid [LogicValues] with [length] number of bits.
  ///
  /// [length] must be greater than or equal to 0.
  static LogicValues fromInt(int value, int length) =>
      _SmallLogicValues(value, 0, length);

  /// Converts `BigInt` [value] to a valid [LogicValues] with [length] number of bits.
  ///
  /// [length] must be greater than or equal to 0.
  static LogicValues fromBigInt(BigInt value, int length) =>
      _BigLogicValues(value, BigInt.zero, length);

  /// Constructs a [LogicValues] with the [length] number of bits, where every bit has the same value of [fill].
  ///
  /// [length] must be greater than or equal to 0.
  static LogicValues filled(int length, LogicValue fill) =>
      _FilledLogicValues(fill, length);

  /// Constructs a [LogicValues] from [it].
  ///
  /// The order of the created [LogicValues] will be such that the `i`th entry in [it] corresponds
  /// to the `i`th bit.  That is, the 0th element of [it] will be the 0th bit of the returned [LogicValues].
  ///
  /// ```dart
  /// var it = [LogicValue.zero, LogicValue.x, LogicValue.one];
  /// var lv = LogicValues.from(it);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  static LogicValues from(Iterable<LogicValue> it) => LogicValues.fromString(
      it.map((e) => e.toString()).toList().reversed.join());

  /// Returns true if bits in the [BigInt] are either all 0 or all 1
  static bool _bigIntIsFilled(BigInt x, int length) =>
      (x | _BigLogicValues._maskOfLength(length)) == x;

  /// Returns a [String] representing the `_value` to be used by implementations relying on `_value` and `_invalid`.
  static String _valueString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[xz]'), (m) => m[0] == 'x' ? '0' : '1');

  /// Returns a [String] representing the `_invalid` to be used by implementations relying on `_value` and `_invalid`.
  static String _invalidString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[1xz]'), (m) => m[0] == '1' ? '0' : '1');

  /// Converts a binary [String] representation of a [LogicValues] into a [LogicValues].
  ///
  /// The [stringRepresentation] should only contain bit values (e.g. no `0b` at the start).
  /// The order of the created [LogicValues] will be such that the `i`th character in [stringRepresentation]
  /// corresponds to the `length - i - 1`th bit.  That is, the last character of [stringRepresentation] will be
  /// the 0th bit of the returned [LogicValues].
  ///
  /// ```dart
  /// var stringRepresentation = '1x0';
  /// var lv = LogicValues.fromString(stringRepresentation);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  static LogicValues fromString(String stringRepresentation) {
    var valueString = _valueString(stringRepresentation);
    var invalidString = _invalidString(stringRepresentation);
    var length = stringRepresentation.length;
    if (length <= _INT_BITS) {
      var value = int.parse(valueString, radix: 2);
      var invalid = int.parse(invalidString, radix: 2);
      //TODO: check if we should use filled here
      return _SmallLogicValues(value, invalid, length);
    } else {
      var value = BigInt.parse(valueString, radix: 2);
      var invalid = BigInt.parse(invalidString, radix: 2);
      if (invalid.sign == 0) {
        if (value.sign == 0) {
          return LogicValues.filled(length, LogicValue.zero);
        } else if (_bigIntIsFilled(value, length)) {
          return LogicValues.filled(length, LogicValue.one);
        }
      } else if (_bigIntIsFilled(invalid, length)) {
        if (value.sign == 0) {
          return LogicValues.filled(length, LogicValue.x);
        } else if (_bigIntIsFilled(value, length)) {
          return LogicValues.filled(length, LogicValue.z);
        }
      }
      return _BigLogicValues(value, invalid, length);
    }
  }

  /// Returns true iff the length and all bits of [this] are equal to [other].
  @override
  bool operator ==(Object other) {
    if (other is! LogicValues) return false;
    if (other.length != length) return false;
    return _equals(other);
  }

  /// Returns true iff all bits of [this] are equal to [other].
  bool _equals(Object other);

  @override
  int get hashCode => _hashCode;
  int get _hashCode;

  /// Returns a this [LogicValues] as a [List<LogicValue>].
  ///
  /// The order of the created [List] will be such that the `i`th entry of it corresponds
  /// to the `i`th bit.  That is, the 0th element of the list will be the 0th bit of this [LogicValues].
  ///
  /// ```dart
  /// var lv = LogicValues.fromString('1x0');
  /// var it = lv.toList();
  /// print(lv); // This prints `[LogicValue.zero, LogicValue.x, LogicValue.one]`
  /// ```
  List<LogicValue> toList() =>
      List<LogicValue>.generate(length, (index) => this[index]).toList();

  /// Converts this [LogicValues] to a [String], including a decorator at the front in SystemVerilog style.
  ///
  /// The first digits before the `b` are the length of the value.
  ///
  /// ```dart
  /// var lv = LogicValues.fromString('1x0');
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @override
  String toString() =>
      "$length'b" +
      List<String>.generate(length, (index) => this[index].toString())
          .reversed
          .join();

  /// Returns the `i`th bit of this [LogicValues]
  LogicValue operator [](int index) {
    if (index >= length || index < 0) {
      throw IndexError(index, this, 'LogicValuesIndexOutOfRange',
          'Index out of range: $index.', length);
    }
    return _getIndex(index);
  }

  /// Returns the `i`th bit of this [LogicValues].  Performs no boundary checks.
  LogicValue _getIndex(int index);

  /// Returns a new `LogicValues` with the order of all bits in the reverse order of this `LogicValues`
  LogicValues get reversed;

  /// Returns a subset [LogicValues].  It is inclusive of [start], exclusive of [end].
  LogicValues getRange(int start, int end) {
    if (end < start) throw Exception('End cannot be greater than start.');
    if (end > length) throw Exception('End must be less than length.');
    if (start < 0) throw Exception('Start must be greater than or equal to 0.');
    return _getRange(start, end);
  }

  /// Returns a subset [LogicValues].  It is inclusive of [start], exclusive of [end].  Performs no boundary checks.
  LogicValues _getRange(int start, int end);

  /// Converts a pair of `_value` and `_invalid` into a [LogicValue].
  LogicValue _bitsToLogicValue(bool bitValue, bool bitInvalid) => bitInvalid
      ? (bitValue ? LogicValue.z : LogicValue.x)
      : (bitValue ? LogicValue.one : LogicValue.zero);

  /// True iff all bits are `0` or `1`, not a single `x` or `z`.
  bool get isValid;

  /// True iff all bits are `z`.
  bool get isFloating;

  /// The current active value of this if it has width 1, as a [LogicValue].
  ///
  /// Throws an Exception if width is not 1.
  LogicValue get bit {
    if (length != 1) throw Exception('Length is not 1');
    return this[0];
  }

  /// Converts valid a [LogicValues] to an [int].
  ///
  /// Throws an `Exception` if not [isValid] or the length doesn't fit in an [int].
  int toInt();

  /// Converts valid a [LogicValues] to an [int].
  ///
  /// Throws an `Exception` if not [isValid].
  BigInt toBigInt();

  /// Returns a new [LogicValues] with every bit inverted.
  ///
  /// All invalid bits (`x` or `z`) are converted to `x`.
  LogicValues operator ~();

  /// Bitwise AND operation.
  LogicValues operator &(LogicValues other) =>
      _twoInputBitwiseOp(other, (a, b) => a._and2(b));

  /// Bitwise OR operation.
  LogicValues operator |(LogicValues other) =>
      _twoInputBitwiseOp(other, (a, b) => a._or2(b));

  /// Bitwise XOR operation.
  LogicValues operator ^(LogicValues other) =>
      _twoInputBitwiseOp(other, (a, b) => a._xor2(b));

  /// Bitwise AND operation.  No length comparison.
  LogicValues _and2(LogicValues other);

  /// Bitwise OR operation.  No length comparison.
  LogicValues _or2(LogicValues other);

  /// Bitwise XOR operation.  No length comparison.
  LogicValues _xor2(LogicValues other);

  LogicValues _twoInputBitwiseOp(
      LogicValues other, LogicValues Function(LogicValues, LogicValues) op) {
    if (length != other.length) throw Exception('Lengths must match');
    if (other is _FilledLogicValues && this is! _FilledLogicValues) {
      return op(other, this);
    }
    return op(this, other);
  }

  /// Unary AND operation.
  ///
  /// Returns `1` iff all bits are `1`.
  /// Returns `x` iff all bits are either `1` or invalid.
  /// Returns `0` otherwise.
  LogicValue and();

  /// Unary OR operation.
  ///
  /// Returns `1` iff any bit is `1`.
  /// Returns `x` iff all bits are either `0` or invalid.
  /// Returns `0` otherwise.
  LogicValue or();

  /// Unary XOR operation.
  ///
  /// Returns `x` if any bit is invalid.
  LogicValue xor();

  //TODO: finish implementing and testing signed math.

  /// Addition operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValues operator +(dynamic other) => _doMath(other, (a, b) => a + b);

  /// Subtraction operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValues operator -(dynamic other) => _doMath(other, (a, b) => a - b);

  /// Multiplication operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValues operator *(dynamic other) => _doMath(other, (a, b) => a * b);

  /// Division operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValues operator /(dynamic other) => _doMath(other, (a, b) => a ~/ b);

  /// Executes mathematical operations between two [LogicValues]s
  ///
  /// Handles length and bounds checks as well as proper conversion between different types of representation.
  LogicValues _doMath(
      dynamic other, dynamic Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValues || other is BigInt)) {
      throw Exception('Improper argument ${other.runtimeType}');
    }
    if (other is LogicValues && other.length != length) {
      throw Exception('Lengths must match');
    }

    if (!isValid) return LogicValues.filled(length, LogicValue.x);
    if (other is LogicValues && !other.isValid) {
      return LogicValues.filled(other.length, LogicValue.x);
    }

    if (this is _BigLogicValues ||
        other is BigInt ||
        other is _BigLogicValues) {
      var a = toBigInt();
      var b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other)
              : other is LogicValues
                  ? other.toBigInt()
                  : throw Exception('Unexpected big type.');
      return LogicValues.fromBigInt(op(a, b), length);
    } else {
      var a = toInt();
      var b = other is int ? other : (other as LogicValues).toInt();
      return LogicValues.fromInt(op(a, b), length);
    }
  }

  /// Equal-to operation.
  ///
  /// This is different from [==] because it returns a [LogicValue] instead of a [bool].
  /// It does a logical comparison of the two values, rather than exact equality.  For
  /// example, if one of the two values is invalid, [eq] will return `x`.
  LogicValue eq(dynamic other) => _doCompare(other, (a, b) => a == b);

  /// Less-than operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator <(dynamic other) => _doCompare(other, (a, b) => a < b);

  /// Greater-than operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator >(dynamic other) => _doCompare(other, (a, b) => a > b);

  /// Less-than-or-equal operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator <=(dynamic other) => _doCompare(other, (a, b) => a <= b);

  /// Greater-than-or-equal operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator >=(dynamic other) => _doCompare(other, (a, b) => a >= b);

  /// Executes comparison operations between two [LogicValues]s
  ///
  /// Handles length and bounds checks as well as proper conversion between different types of representation.
  LogicValue _doCompare(dynamic other, bool Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValues || other is BigInt)) {
      throw Exception('Improper arguments ${other.runtimeType}.');
    }
    if (other is LogicValues && other.length != length) {
      throw Exception('Lengths must match');
    }

    if (!isValid) return LogicValue.x;
    if (other is LogicValues && !other.isValid) return LogicValue.x;

    dynamic a, b;
    if (this is _BigLogicValues ||
        other is BigInt ||
        other is _BigLogicValues) {
      a = toBigInt();
      b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other)
              : other is LogicValues
                  ? other.toBigInt()
                  : throw Exception('Unexpected big type.');
    } else {
      a = toInt();
      b = other is int ? other : (other as LogicValues).toInt();
    }
    return op(a, b) ? LogicValue.one : LogicValue.zero;
  }

  //TODO: test shift operations on INT_BITS width busses to make sure it works right

  /// Arithmetic right-shift operation.
  LogicValues operator >>(dynamic shamt) =>
      _shift(shamt, _ShiftType.arithmeticRight);

  /// Logical left-shift operation.
  LogicValues operator <<(dynamic shamt) => _shift(shamt, _ShiftType.left);

  /// Logical right-shift operation.
  LogicValues operator >>>(dynamic shamt) => _shift(shamt, _ShiftType.right);

  /// Performs shift operations in the specified direction
  LogicValues _shift(dynamic shamt, _ShiftType direction) {
    int shamtInt;
    if (shamt is LogicValues) {
      if (!shamt.isValid) return LogicValues.filled(length, LogicValue.x);
      shamtInt = shamt.toInt();
    } else if (shamt is int) {
      shamtInt = shamt;
    } else {
      throw Exception('Cannot shift by type ${shamt.runtimeType}');
    }
    if (direction == _ShiftType.left) {
      return _shiftLeft(shamtInt);
    } else if (direction == _ShiftType.right) {
      return _shiftRight(shamtInt);
    } else {
      //if(direction == ShiftType.ArithmeticRight) {
      return _shiftArithmeticRight(shamtInt);
    }
  }

  /// Logical right-shift operation by an [int].
  LogicValues _shiftRight(int shamt);

  /// Logical left-shift operation by an [int].
  LogicValues _shiftLeft(int shamt);

  /// Arithmetic right-shift operation by an [int].
  LogicValues _shiftArithmeticRight(int shamt);
}

/// Enum for direction of shift
enum _ShiftType { left, right, arithmeticRight }
