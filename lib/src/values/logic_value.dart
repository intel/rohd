/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_values.dart
/// Definitions for a set of logical values of any width
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

part of values;

@Deprecated('Use `LogicValue` instead.'
    '  `LogicValues` and `LogicValue` have been merged into one type.')
typedef LogicValues = LogicValue;

/// An immutable 4-value representation of an arbitrary number of bits.
///
/// Each bit of [LogicValue] can be represented as a [LogicValue] of `0`, `1`, `x` (contention), or `z` (floating).
@Immutable()
abstract class LogicValue {
  /// The number of bits in an int.
  // ignore: constant_identifier_names
  static const int _INT_BITS = 64;

  /// Logical value of `0`
  static const LogicValue zero = _FilledLogicValue(_LogicValueEnum.zero, 1);

  /// Logical value of `1`
  static const LogicValue one = _FilledLogicValue(_LogicValueEnum.one, 1);

  /// Logical value of `x`
  static const LogicValue x = _FilledLogicValue(_LogicValueEnum.x, 1);

  /// Logical value of `z`
  static const LogicValue z = _FilledLogicValue(_LogicValueEnum.z, 1);

  /// The number of bits in this `LogicValue`.
  final int width;

  /// The number of bits in this `LogicValue`.
  @Deprecated('Use `width` instead.')
  int get length => width;

  const LogicValue._(this.width) : assert(width >= 0);

  /// Converts `bool` [value] to a valid [LogicValue] with 1 bits either one or zero.
  static LogicValue ofBool(bool value) => value ? one : zero;

  /// Converts `bool` [value] to a valid [LogicValue] with 1 bits either one or zero.
  @Deprecated('Use `ofBool` instead.')
  static LogicValue fromBool(bool value) => ofBool(value);

  /// Converts `int` [value] to a valid [LogicValue] with [width] number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  static LogicValue ofInt(int value, int width) => width > _INT_BITS
      ? _BigLogicValue(BigInt.from(value), BigInt.zero, width)
      : _SmallLogicValue(value, 0, width);

  /// Converts `int` [value] to a valid [LogicValue] with [width] number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  @Deprecated('Use `ofInt` instead.')
  static LogicValue fromInt(int value, int width) => ofInt(value, width);

  /// Converts `BigInt` [value] to a valid [LogicValue] with [width] number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  static LogicValue ofBigInt(BigInt value, int width) => width > _INT_BITS
      ? _BigLogicValue(value, BigInt.zero, width)
      : _SmallLogicValue(value.toInt(), 0, width);

  /// Converts `BigInt` [value] to a valid [LogicValue] with [width] number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  @Deprecated('Use `ofBigInt` instead.')
  static LogicValue fromBigInt(BigInt value, int width) =>
      ofBigInt(value, width);

  /// Constructs a [LogicValue] with the [width] number of bits, where every bit has the same value of [fill].
  ///
  /// [width] must be greater than or equal to 0.
  static LogicValue filled(int width, LogicValue fill) =>
      _FilledLogicValue(fill._enum, width);

  _LogicValueEnum get _enum {
    if (width != 1) {
      throw Exception(
          'Cannot convert value of width $width to a single bit value.');
    }
    return this == LogicValue.one
        ? _LogicValueEnum.one
        : this == LogicValue.zero
            ? _LogicValueEnum.zero
            : this == LogicValue.x
                ? _LogicValueEnum.x
                : this == LogicValue.z
                    ? _LogicValueEnum.z
                    : throw Exception('Failed to convert.');
  }

  /// Constructs a [LogicValue] from [it].
  ///
  /// The order of the created [LogicValue] will be such that the `i`th entry in [it] corresponds
  /// to the `i`th bit.  That is, the 0th element of [it] will be the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var it = [LogicValue.zero, LogicValue.x, LogicValue.one];
  /// var lv = LogicValue.of(it);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  static LogicValue of(Iterable<LogicValue> it) => LogicValue.ofString(
      it.map((e) => e.toString(includeWidth: false)).toList().reversed.join());

  /// Constructs a [LogicValue] from [it].
  ///
  /// The order of the created [LogicValue] will be such that the `i`th entry in [it] corresponds
  /// to the `i`th bit.  That is, the 0th element of [it] will be the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var it = [LogicValue.zero, LogicValue.x, LogicValue.one];
  /// var lv = LogicValue.from(it);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @Deprecated('Use `of` instead.')
  static LogicValue from(Iterable<LogicValue> it) => of(it);

  /// Returns true if bits in the [BigInt] are either all 0 or all 1
  static bool _bigIntIsFilled(BigInt x, int width) =>
      (x | _BigLogicValue._maskOfWidth(width)) == x;

  /// Returns a [String] representing the `_value` to be used by implementations relying on `_value` and `_invalid`.
  static String _valueString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[xz]'), (m) => m[0] == 'x' ? '0' : '1');

  /// Returns a [String] representing the `_invalid` to be used by implementations relying on `_value` and `_invalid`.
  static String _invalidString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[1xz]'), (m) => m[0] == '1' ? '0' : '1');

  /// Converts a binary [String] representation of a [LogicValue] into a [LogicValue].
  ///
  /// The [stringRepresentation] should only contain bit values (e.g. no `0b` at the start).
  /// The order of the created [LogicValue] will be such that the `i`th character in [stringRepresentation]
  /// corresponds to the `length - i - 1`th bit.  That is, the last character of [stringRepresentation] will be
  /// the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var stringRepresentation = '1x0';
  /// var lv = LogicValue.ofString(stringRepresentation);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  static LogicValue ofString(String stringRepresentation) {
    if (stringRepresentation.isEmpty) {
      return _SmallLogicValue(0, 0, 0);
    }

    var valueString = _valueString(stringRepresentation);
    var invalidString = _invalidString(stringRepresentation);
    var width = stringRepresentation.length;

    if (width <= _INT_BITS) {
      var value = int.parse(valueString, radix: 2);
      var invalid = int.parse(invalidString, radix: 2);
      return _SmallLogicValue(value, invalid, width);
    } else {
      var value = BigInt.parse(valueString, radix: 2);
      var invalid = BigInt.parse(invalidString, radix: 2);
      if (invalid.sign == 0) {
        if (value.sign == 0) {
          return LogicValue.filled(width, LogicValue.zero);
        } else if (_bigIntIsFilled(value, width)) {
          return LogicValue.filled(width, LogicValue.one);
        }
      } else if (_bigIntIsFilled(invalid, width)) {
        if (value.sign == 0) {
          return LogicValue.filled(width, LogicValue.x);
        } else if (_bigIntIsFilled(value, width)) {
          return LogicValue.filled(width, LogicValue.z);
        }
      }
      return _BigLogicValue(value, invalid, width);
    }
  }

  /// Converts a binary [String] representation of a [LogicValue] into a [LogicValue].
  ///
  /// The [stringRepresentation] should only contain bit values (e.g. no `0b` at the start).
  /// The order of the created [LogicValue] will be such that the `i`th character in [stringRepresentation]
  /// corresponds to the `length - i - 1`th bit.  That is, the last character of [stringRepresentation] will be
  /// the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var stringRepresentation = '1x0';
  /// var lv = LogicValue.fromString(stringRepresentation);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @Deprecated('Use `ofString` instead.')
  static LogicValue fromString(String stringRepresentation) =>
      ofString(stringRepresentation);

  /// Returns true iff the width and all bits of [this] are equal to [other].
  @override
  bool operator ==(Object other) {
    if (other is! LogicValue) return false;
    if (other.width != width) return false;
    return _equals(other);
  }

  /// Returns true iff all bits of [this] are equal to [other].
  bool _equals(Object other);

  @override
  int get hashCode => _hashCode;
  int get _hashCode;

  /// Returns a this [LogicValue] as a [List<LogicValue>] where every element is 1 bit.
  ///
  /// The order of the created [List] will be such that the `i`th entry of it corresponds
  /// to the `i`th bit.  That is, the 0th element of the list will be the 0th bit of this [LogicValue].
  ///
  /// ```dart
  /// var lv = LogicValue.ofString('1x0');
  /// var it = lv.toList();
  /// print(lv); // This prints `[1'h0, 1'bx, 1'h1]`
  /// ```
  List<LogicValue> toList() =>
      List<LogicValue>.generate(width, (index) => this[index]).toList();

  /// Converts this [LogicValue] to a binary [String], including a decorator at the front
  /// in SystemVerilog style.
  ///
  /// The first digits before the `b` (for binary) or `h` (for hex) are the width
  /// of the value.  If [includeWidth] is set to false, then the width of the bus and
  /// decorator will not be included in the generated String and it will print in binary.
  ///
  /// ```dart
  /// var lv = LogicValue.ofString('1x0');
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @override
  String toString({bool includeWidth = true}) => isValid && includeWidth
      ? "$width'h" +
          (width > _INT_BITS
              ? toBigInt().toRadixString(16)
              : toInt().toRadixString(16))
      : [
          if (includeWidth) "$width'b",
          List<String>.generate(width, (index) => this[index]._bitString())
              .reversed
              .join()
        ].join();

  String _bitString() {
    if (width != 1) {
      throw Exception(
          'Cannot convert value of width $width to a single bit value.');
    }
    return this == LogicValue.x
        ? 'x'
        : this == LogicValue.z
            ? 'z'
            : this == LogicValue.one
                ? '1'
                : '0';
  }

  /// Returns the `i`th bit of this [LogicValue]
  LogicValue operator [](int index) {
    if (index >= width || index < 0) {
      throw IndexError(index, this, 'LogicValueIndexOutOfRange',
          'Index out of range: $index.', width);
    }
    return _getIndex(index);
  }

  /// Returns the `i`th bit of this [LogicValue].  Performs no boundary checks.
  LogicValue _getIndex(int index);

  /// Returns a new [LogicValue] with the order of all bits in the reverse order of this [LogicValue]
  LogicValue get reversed;

  /// Returns a subset [LogicValue].  It is inclusive of [startIndex], exclusive of [endIndex].
  ///
  /// [startIndex] must be less than [endIndex]. If [startIndex] and [endIndex] are equal, then a
  /// zero-width value is returned.
  LogicValue getRange(int startIndex, int endIndex) {
    if (endIndex < startIndex) {
      throw Exception(
          'End ($endIndex) cannot be less than start ($startIndex).');
    }
    if (endIndex > width) {
      throw Exception('End ($endIndex) must be less than width ($width).');
    }
    if (startIndex < 0) {
      throw Exception(
          'Start ($startIndex) must be greater than or equal to 0.');
    }
    return _getRange(startIndex, endIndex);
  }

  /// Returns a subset [LogicValue].  It is inclusive of [start], exclusive of [end].
  /// Performs no boundary checks.
  ///
  /// If [start] and [end] are equal, then a zero-width signal is returned.
  LogicValue _getRange(int start, int end);

  /// Accesses a subset of this [LogicValue] from [startIndex] to [endIndex], both inclusive.
  ///
  /// If [endIndex] is less than [startIndex], the returned value will be reversed relative
  /// to the original value.
  LogicValue slice(int endIndex, int startIndex) {
    if (startIndex <= endIndex) {
      return getRange(startIndex, endIndex + 1);
    } else {
      return getRange(endIndex, startIndex + 1).reversed;
    }
  }

  /// Converts a pair of `_value` and `_invalid` into a [LogicValue].
  LogicValue _bitsToLogicValue(bool bitValue, bool bitInvalid) => bitInvalid
      ? (bitValue ? LogicValue.z : LogicValue.x)
      : (bitValue ? LogicValue.one : LogicValue.zero);

  /// True iff all bits are `0` or `1`, not a single `x` or `z`.
  bool get isValid;

  /// True iff all bits are `z`.
  bool get isFloating;

  /// The current active value of this, if it has width 1, as a [LogicValue].
  ///
  /// Throws an Exception if width is not 1.
  @Deprecated('Check `width` separately to see if single-bit.')
  LogicValue get bit {
    if (width != 1) throw Exception('Width must be 1, but was $width.');
    return this;
  }

  /// Converts valid a [LogicValue] to an [int].
  ///
  /// Throws an `Exception` if not [isValid] or the width doesn't fit in an [int].
  int toInt();

  /// Converts valid a [LogicValue] to an [int].
  ///
  /// Throws an `Exception` if not [isValid].
  BigInt toBigInt();

  /// Converts a valid logical value to a boolean.
  ///
  /// Throws an exception if the value is invalid.
  bool toBool() {
    if (!isValid) throw Exception('Cannot convert value "$this" to bool');
    if (width != 1) {
      throw Exception(
          'Only single bit values can be converted to a bool, but found width $width in $this');
    }
    return this == LogicValue.one ? true : false;
  }

  /// Returns a new [LogicValue] with every bit inverted.
  ///
  /// All invalid bits (`x` or `z`) are converted to `x`.
  LogicValue operator ~();

  /// Bitwise AND operation.
  LogicValue operator &(LogicValue other) =>
      _twoInputBitwiseOp(other, (a, b) => a._and2(b));

  /// Bitwise OR operation.
  LogicValue operator |(LogicValue other) =>
      _twoInputBitwiseOp(other, (a, b) => a._or2(b));

  /// Bitwise XOR operation.
  LogicValue operator ^(LogicValue other) =>
      _twoInputBitwiseOp(other, (a, b) => a._xor2(b));

  /// Bitwise AND operation.  No width comparison.
  LogicValue _and2(LogicValue other);

  /// Bitwise OR operation.  No width comparison.
  LogicValue _or2(LogicValue other);

  /// Bitwise XOR operation.  No width comparison.
  LogicValue _xor2(LogicValue other);

  LogicValue _twoInputBitwiseOp(
      LogicValue other, LogicValue Function(LogicValue, LogicValue) op) {
    if (width != other.width) {
      throw Exception('Widths must match, but found $this and $other');
    }
    if (other is _FilledLogicValue && this is! _FilledLogicValue) {
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

  /// Addition operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator +(dynamic other) => _doMath(other, (a, b) => a + b);

  /// Subtraction operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator -(dynamic other) => _doMath(other, (a, b) => a - b);

  /// Multiplication operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator *(dynamic other) => _doMath(other, (a, b) => a * b);

  /// Division operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator /(dynamic other) => _doMath(other, (a, b) => a ~/ b);

  /// Executes mathematical operations between two [LogicValue]s
  ///
  /// Handles width and bounds checks as well as proper conversion between different types of representation.
  LogicValue _doMath(dynamic other, dynamic Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw Exception(
          'Improper argument ${other.runtimeType}, should be int, LogicValue, or BigInt.');
    }
    if (other is LogicValue && other.width != width) {
      throw Exception('Widths  must match, but found "$this" and "$other".');
    }

    if (!isValid) return LogicValue.filled(width, LogicValue.x);
    if (other is LogicValue && !other.isValid) {
      return LogicValue.filled(other.width, LogicValue.x);
    }

    if (this is _BigLogicValue || other is BigInt || other is _BigLogicValue) {
      var a = toBigInt();
      var b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other)
              : other is LogicValue
                  ? other.toBigInt()
                  : throw Exception(
                      'Unexpected big type: ${other.runtimeType}.');
      return LogicValue.ofBigInt(op(a, b), width);
    } else {
      var a = toInt();
      var b = other is int ? other : (other as LogicValue).toInt();
      return LogicValue.ofInt(op(a, b), width);
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

  /// Executes comparison operations between two [LogicValue]s
  ///
  /// Handles width and bounds checks as well as proper conversion between different types of representation.
  LogicValue _doCompare(dynamic other, bool Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw Exception(
          'Improper arguments ${other.runtimeType}, should be int, LogicValue, or BigInt.');
    }
    if (other is LogicValue && other.width != width) {
      throw Exception('Widths must match, but found "$this" and "$other"');
    }

    if (!isValid) return LogicValue.x;
    if (other is LogicValue && !other.isValid) return LogicValue.x;

    dynamic a, b;
    if (this is _BigLogicValue || other is BigInt || other is _BigLogicValue) {
      a = toBigInt();
      b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other)
              : other is LogicValue
                  ? other.toBigInt()
                  : throw Exception(
                      'Unexpected big type: ${other.runtimeType}.');
    } else {
      a = toInt();
      b = other is int ? other : (other as LogicValue).toInt();
    }
    return op(a, b) ? LogicValue.one : LogicValue.zero;
  }

  /// Arithmetic right-shift operation.
  LogicValue operator >>(dynamic shamt) =>
      _shift(shamt, _ShiftType.arithmeticRight);

  /// Logical left-shift operation.
  LogicValue operator <<(dynamic shamt) => _shift(shamt, _ShiftType.left);

  /// Logical right-shift operation.
  LogicValue operator >>>(dynamic shamt) => _shift(shamt, _ShiftType.right);

  /// Performs shift operations in the specified direction
  LogicValue _shift(dynamic shamt, _ShiftType direction) {
    if (width == 0) return this;
    int shamtInt;
    if (shamt is LogicValue) {
      if (!shamt.isValid) return LogicValue.filled(width, LogicValue.x);
      shamtInt = shamt.toInt();
    } else if (shamt is int) {
      shamtInt = shamt;
    } else {
      throw Exception('Cannot shift by type ${shamt.runtimeType}.');
    }
    if (direction == _ShiftType.left) {
      return _shiftLeft(shamtInt);
    } else if (direction == _ShiftType.right) {
      return _shiftRight(shamtInt);
    } else {
      // if(direction == ShiftType.ArithmeticRight) {
      return _shiftArithmeticRight(shamtInt);
    }
  }

  /// Logical right-shift operation by an [int].
  LogicValue _shiftRight(int shamt);

  /// Logical left-shift operation by an [int].
  LogicValue _shiftLeft(int shamt);

  /// Arithmetic right-shift operation by an [int].
  LogicValue _shiftArithmeticRight(int shamt);

  static void _assertSingleBit(LogicValue value) {
    if (value.width != 1) {
      throw Exception('Expected a single-bit value but found $value.');
    }
  }

  /// Returns true iff the transition represents a positive edge.
  ///
  /// Only returns true from 0 -> 1.  If [previousValue] or [newValue] is invalid, an Exception will be
  /// thrown, unless [ignoreInvalid] is set to `true`.
  static bool isPosedge(LogicValue previousValue, LogicValue newValue,
      {ignoreInvalid = false}) {
    _assertSingleBit(previousValue);
    _assertSingleBit(newValue);

    if (!ignoreInvalid && (!previousValue.isValid | !newValue.isValid)) {
      throw Exception(
          'Edge detection on invalid value from $previousValue to $newValue.');
    }
    return previousValue == LogicValue.zero && newValue == LogicValue.one;
  }

  /// Returns true iff the transition represents a negative edge.
  ///
  /// Only returns true from 1 -> 0.  If [previousValue] or [newValue] is invalid, an Exception will be
  /// thrown, unless [ignoreInvalid] is set to `true`.
  static bool isNegedge(LogicValue previousValue, LogicValue newValue,
      {ignoreInvalid = false}) {
    _assertSingleBit(previousValue);
    _assertSingleBit(newValue);

    if (!ignoreInvalid && (!previousValue.isValid | !newValue.isValid)) {
      throw Exception(
          'Edge detection on invalid value from $previousValue to $newValue');
    }
    return previousValue == LogicValue.one && newValue == LogicValue.zero;
  }

  /// Returns a new [LogicValue] with width [newWidth] where the most significant
  /// bits for indices beyond the original [width] are set to [fill].
  ///
  /// The [newWidth] must be greater than or equal to the current width or an exception
  /// will be thrown. [fill] must be a single bit ([width]=1).
  LogicValue extend(int newWidth, LogicValue fill) {
    if (newWidth < width) {
      throw Exception(
          'New width $newWidth must be greater than or equal to width $width.');
    }
    if (fill.width != 1) {
      throw Exception('The fill must be 1 bit, but got $fill.');
    }
    return [
      LogicValue.filled(newWidth - width, fill),
      this,
    ].swizzle();
  }

  /// Returns a new [LogicValue] with width [newWidth] where new bits added are zeros
  /// as the most significant bits.
  ///
  /// The [newWidth] must be greater than or equal to the current width or an exception
  /// will be thrown.
  LogicValue zeroExtend(int newWidth) {
    return extend(newWidth, LogicValue.zero);
  }

  /// Returns a new [LogicValue] with width [newWidth] where new bits added are sign bits
  /// as the most significant bits.  The sign is determined using two's complement, so
  /// it takes the most significant bit of the original value and extends with that.
  ///
  /// The [newWidth] must be greater than or equal to the current width or an exception
  /// will be thrown.
  LogicValue signExtend(int newWidth) {
    return extend(newWidth, this[width - 1]);
  }

  /// Returns a copy of this [LogicValue] with the bits starting from [startIndex]
  /// up until [startIndex] + [update]`.width` set to [update] instead
  /// of their original value.
  ///
  /// The return value will be the same [width].  An exception will be thrown if
  /// the position of the [update] would cause an overrun past the [width].
  LogicValue withSet(int startIndex, LogicValue update) {
    if (startIndex + update.width > width) {
      throw Exception(
          'Width of updatedValue $update at startIndex $startIndex would'
          'overrun the width of the original ($width).');
    }

    return [
      getRange(startIndex + update.width, width),
      update,
      getRange(0, startIndex),
    ].swizzle();
  }
}

/// Enum for direction of shift
enum _ShiftType { left, right, arithmeticRight }

/// Converts a binary [String] representation to a binary [int].
///
/// Ignores all '_' in the provided binary.
int bin(String s) => int.parse(s.replaceAll('_', ''), radix: 2);

/// Enum for a [LogicValue]'s value.
enum _LogicValueEnum { zero, one, x, z }
