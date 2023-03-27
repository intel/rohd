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

/// Deprecated: use [LogicValue] instead.
@Deprecated('Use `LogicValue` instead.'
    '  `LogicValues` and `LogicValue` have been merged into one type.')
typedef LogicValues = LogicValue;

/// An immutable 4-value representation of an arbitrary number of bits.
///
/// Each bit of [LogicValue] can be represented as a [LogicValue]
/// of `0`, `1`, `x` (contention), or `z` (floating).
@immutable
abstract class LogicValue {
  /// The number of bits in an int.
  // ignore: constant_identifier_names
  static const int _INT_BITS = 64;

  /// Logical value of `0`.
  static const LogicValue zero = _FilledLogicValue(_LogicValueEnum.zero, 1);

  /// Logical value of `1`.
  static const LogicValue one = _FilledLogicValue(_LogicValueEnum.one, 1);

  /// Logical value of `x`.
  static const LogicValue x = _FilledLogicValue(_LogicValueEnum.x, 1);

  /// Logical value of `z`.
  static const LogicValue z = _FilledLogicValue(_LogicValueEnum.z, 1);

  /// A zero-width value.
  static const LogicValue empty = _FilledLogicValue(_LogicValueEnum.zero, 0);

  /// The number of bits in this `LogicValue`.
  final int width;

  /// The number of bits in this `LogicValue`.
  @Deprecated('Use `width` instead.')
  int get length => width;

  const LogicValue._(this.width)
      : assert(width >= 0, 'Width must be greater than or equal to 0.');

  /// Converts `bool` [value] to a valid [LogicValue] with 1 bits either
  /// one or zero.
  // ignore: avoid_positional_boolean_parameters
  static LogicValue ofBool(bool value) => value ? one : zero;

  /// Converts `bool` [value] to a valid [LogicValue] with 1 bits either
  /// one or zero.
  @Deprecated('Use `ofBool` instead.')
  // ignore: avoid_positional_boolean_parameters
  static LogicValue fromBool(bool value) => ofBool(value);

  /// Converts `int` [value] to a valid [LogicValue] with [width] number
  /// of bits.
  ///
  /// [width] must be greater than or equal to 0.
  static LogicValue ofInt(int value, int width) => width > _INT_BITS
      ? _bigLogicValueOrFilled(BigInt.from(value), BigInt.zero, width)
      : _smallLogicValueOrFilled(value, 0, width);

  /// Converts `int` [value] to a valid [LogicValue] with [width]
  /// number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  @Deprecated('Use `ofInt` instead.')
  static LogicValue fromInt(int value, int width) => ofInt(value, width);

  /// Converts `BigInt` [value] to a valid [LogicValue] with [width]
  /// number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  static LogicValue ofBigInt(BigInt value, int width) => width > _INT_BITS
      ? _bigLogicValueOrFilled(value, BigInt.zero, width)
      : _smallLogicValueOrFilled(value.toIntUnsigned(width), 0, width);

  /// Converts `BigInt` [value] to a valid [LogicValue] with [width]
  /// number of bits.
  ///
  /// [width] must be greater than or equal to 0.
  @Deprecated('Use `ofBigInt` instead.')
  static LogicValue fromBigInt(BigInt value, int width) =>
      ofBigInt(value, width);

  /// Constructs a [LogicValue] with the [width] number of bits, where every
  /// bit has the same value of [fill].
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
  /// The order of the created [LogicValue] will be such that the `i`th entry in
  /// [it] corresponds to the `i`th group of bits.  That is, the 0th element of
  /// [it] will be the least significant chunk of bits of the returned
  /// [LogicValue].  Bits within each element of [it] are kept in the same
  /// order as they were originally.
  ///
  /// For example:
  /// ```dart
  /// var it = [LogicValue.zero, LogicValue.x, LogicValue.ofString('01xz')];
  /// var lv = LogicValue.of(it);
  /// print(lv); // This prints `6'b01xzx0`
  /// ```
  static LogicValue of(Iterable<LogicValue> it) {
    var smallBuffer = LogicValue.empty;
    var fullResult = LogicValue.empty;

    // shift small chunks in together before shifting BigInt's, since
    // shifting BigInt's is expensive
    for (final lv in it) {
      final lvPlusSmall = lv.width + smallBuffer.width;
      if (lvPlusSmall <= _INT_BITS) {
        smallBuffer = lv._concatenate(smallBuffer);
      } else {
        // only put 64-bit chunks onto `fullResult`, rest onto `smallBuffer`
        final upperBound =
            _INT_BITS * (lvPlusSmall ~/ _INT_BITS) - smallBuffer.width;
        fullResult = lv
            .getRange(0, upperBound)
            ._concatenate(smallBuffer)
            ._concatenate(fullResult);
        smallBuffer = lv.getRange(upperBound, lv.width);
      }

      assert(smallBuffer.width <= _INT_BITS,
          'Keep smallBuffer small to meet invariants and efficiency');
    }

    // grab what's left
    return smallBuffer._concatenate(fullResult);
  }

  /// Appends [other] to the least significant side of `this`.
  ///
  /// The new value will have `this`'s current value shifted left by
  /// the width of [other].
  LogicValue _concatenate(LogicValue other) {
    if (other.width == 0) {
      // ignore: avoid_returning_this
      return this;
    } else if (width == 0) {
      return other;
    }

    final newWidth = width + other.width;

    if (this is _FilledLogicValue &&
        other is _FilledLogicValue &&
        other[0] == this[0]) {
      // can keep it filled
      return _FilledLogicValue(other._value, newWidth);
    } else if (newWidth > LogicValue._INT_BITS) {
      // BigInt's only
      return _BigLogicValue(_bigIntValue << other.width | other._bigIntValue,
          _bigIntInvalid << other.width | other._bigIntInvalid, newWidth);
    } else {
      // int's ok
      return _SmallLogicValue(_intValue << other.width | other._intValue,
          _intInvalid << other.width | other._intInvalid, newWidth);
    }
  }

  /// Returns `_value` in the form of a [BigInt].
  BigInt get _bigIntValue;

  /// Returns `_invalid` in the form of a [BigInt].
  BigInt get _bigIntInvalid;

  /// Returns `_value` in the form of an [int].
  int get _intValue;

  /// Returns `_invalid` in the form of an [int].
  int get _intInvalid;

  /// Constructs a [LogicValue] from [it].
  ///
  /// The order of the created [LogicValue] will be such that the `i`th entry
  /// in [it] corresponds to the `i`th bit.  That is, the 0th element of [it]
  /// will be the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var it = [LogicValue.zero, LogicValue.x, LogicValue.one];
  /// var lv = LogicValue.from(it);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @Deprecated('Use `of` instead.')
  static LogicValue from(Iterable<LogicValue> it) => of(it);

  /// Returns true if bits in [x] are all 0
  static bool _bigIntIs0(BigInt x, int width) =>
      (x & _BigLogicValue._maskOfWidth(width)) == BigInt.zero;

  /// Returns true if bits in [x] are all 1
  static bool _bigIntIs1s(BigInt x, int width) =>
      (x & _BigLogicValue._maskOfWidth(width)) ==
      _BigLogicValue._maskOfWidth(width);

  /// Returns true if bits in [x] are all 0
  static bool _intIs0(int x, int width) =>
      x & _SmallLogicValue._maskOfWidth(width) == 0;

  /// Returns true if bits in [x] are all 1
  static bool _intIs1s(int x, int width) =>
      x & _SmallLogicValue._maskOfWidth(width) ==
      _SmallLogicValue._maskOfWidth(width);

  /// Returns a [String] representing the `_value` to be used by implementations
  /// relying on `_value` and `_invalid`.
  static String _valueString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[xz]'), (m) => m[0] == 'x' ? '0' : '1');

  /// Returns a [String] representing the `_invalid` to be used by
  /// implementations relying on `_value` and `_invalid`.
  static String _invalidString(String stringRepresentation) =>
      stringRepresentation.replaceAllMapped(
          RegExp('[1xz]'), (m) => m[0] == '1' ? '0' : '1');

  /// Converts a binary [String] representation of a [LogicValue] into a
  /// [LogicValue].
  ///
  /// The [stringRepresentation] should only contain bit values (e.g. no `0b`
  /// at the start). The order of the created [LogicValue] will be such that
  /// the `i`th character in [stringRepresentation] corresponds to the
  /// `length - i - 1`th bit.  That is, the last character of
  /// [stringRepresentation] will be the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var stringRepresentation = '1x0';
  /// var lv = LogicValue.ofString(stringRepresentation);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  static LogicValue ofString(String stringRepresentation) {
    if (stringRepresentation.isEmpty) {
      return const _FilledLogicValue(_LogicValueEnum.zero, 0);
    }

    final valueString = _valueString(stringRepresentation);
    final invalidString = _invalidString(stringRepresentation);
    final width = stringRepresentation.length;

    if (width <= _INT_BITS) {
      final value = _unsignedBinaryParse(valueString);
      final invalid = _unsignedBinaryParse(invalidString);
      return _smallLogicValueOrFilled(value, invalid, width);
    } else {
      final value = BigInt.parse(valueString, radix: 2);
      final invalid = BigInt.parse(invalidString, radix: 2);
      return _bigLogicValueOrFilled(value, invalid, width);
    }
  }

  /// Returns either a [_BigLogicValue] or a [_FilledLogicValue] based on
  /// [value], [invalid], and [width].
  ///
  /// Only use if [width] > [_INT_BITS].
  static LogicValue _bigLogicValueOrFilled(
      BigInt value, BigInt invalid, int width) {
    assert(width > _INT_BITS, 'Should only be used for big values');

    return _filledIfPossible(
          _bigIntIs1s(value, width),
          _bigIntIs0(value, width),
          _bigIntIs1s(invalid, width),
          _bigIntIs0(invalid, width),
          width,
        ) ??
        _BigLogicValue(value, invalid, width);
  }

  /// Returns either a [_BigLogicValue] or a [_FilledLogicValue] based on
  /// [value], [invalid], and [width].
  ///
  /// Only use if [width] <= [_INT_BITS].
  static LogicValue _smallLogicValueOrFilled(
      int value, int invalid, int width) {
    assert(width <= _INT_BITS, 'Should only be used for small values');

    return _filledIfPossible(
          _intIs1s(value, width),
          _intIs0(value, width),
          _intIs1s(invalid, width),
          _intIs0(invalid, width),
          width,
        ) ??
        _SmallLogicValue(value, invalid, width);
  }

  /// Constructs a [_FilledLogicValue] based on whether `value` and `invalid`
  /// are all 1's or all 0's.  If it's not possible to represent the value
  /// as filled, it will return `null`.
  static LogicValue? _filledIfPossible(
      bool value1s, bool value0, bool invalid1s, bool invalid0, int width) {
    if (value0) {
      if (invalid0) {
        return LogicValue.filled(width, LogicValue.zero);
      } else if (invalid1s) {
        return LogicValue.filled(width, LogicValue.x);
      }
    } else if (value1s) {
      if (invalid0) {
        return LogicValue.filled(width, LogicValue.one);
      } else if (invalid1s) {
        return LogicValue.filled(width, LogicValue.z);
      }
    }
    return null;
  }

  /// Converts a binary [String] representation of a [LogicValue] into a
  /// [LogicValue].
  ///
  /// The [stringRepresentation] should only contain bit values (e.g. no `0b`
  /// at the start). The order of the created [LogicValue] will be such that
  /// the `i`th character in [stringRepresentation] corresponds to the
  /// `length - i - 1`th bit.  That is, the last character of
  /// [stringRepresentation] will be the 0th bit of the returned [LogicValue].
  ///
  /// ```dart
  /// var stringRepresentation = '1x0';
  /// var lv = LogicValue.fromString(stringRepresentation);
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @Deprecated('Use `ofString` instead.')
  static LogicValue fromString(String stringRepresentation) =>
      ofString(stringRepresentation);

  /// Returns true iff the width and all bits of `this` are equal to [other].
  @override
  bool operator ==(Object other) {
    if (other is! LogicValue) {
      return false;
    }
    if (other.width != width) {
      return false;
    }
    return _equals(other);
  }

  /// Returns true iff all bits of `this` are equal to [other].
  bool _equals(Object other);

  @override
  int get hashCode => _hashCode;
  int get _hashCode;

  /// Returns a this [LogicValue] as a [List<LogicValue>] where every element
  /// is 1 bit.
  ///
  /// The order of the created [List] will be such that the `i`th entry of it
  /// corresponds to the `i`th bit.  That is, the 0th element of the list will
  /// be the 0th bit of this [LogicValue].
  ///
  /// ```dart
  /// var lv = LogicValue.ofString('1x0');
  /// var it = lv.toList();
  /// print(lv); // This prints `[1'h0, 1'bx, 1'h1]`
  /// ```
  List<LogicValue> toList() =>
      List<LogicValue>.generate(width, (index) => this[index]).toList();

  /// Converts this [LogicValue] to a binary [String], including a decorator at
  /// the front in SystemVerilog style.
  ///
  /// The first digits before the `b` (for binary) or `h` (for hex) are the
  /// width of the value.  If [includeWidth] is set to false, then the width of
  /// the bus and decorator will not be included in the generated String and
  /// it will print in binary.
  ///
  /// ```dart
  /// var lv = LogicValue.ofString('1x0');
  /// print(lv); // This prints `3b'1x0`
  /// ```
  @override
  String toString({bool includeWidth = true}) {
    if (isValid && includeWidth) {
      final hexValue = width > _INT_BITS
          ? toBigInt().toRadixString(16)
          : toInt().toRadixString(16);
      return "$width'h$hexValue";
    } else {
      return [
        if (includeWidth) "$width'b",
        ...List<String>.generate(width, (index) => this[index]._bitString())
            .reversed
      ].join();
    }
  }

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
  ///
  /// The [index] provided can be positive or negative. For positive [index],
  /// the indexing is performed from front of the LogicValue.
  /// For negative [index], the indexing started from last index and
  /// goes to front.
  /// Note: the [index] value must follow, -[width] <= [index] < [width]
  ///
  /// ```dart
  /// LogicValue.ofString('1111')[2];  // == LogicValue.one
  /// LogicValue.ofString('0111')[-1]; // == LogicValue.zero
  /// LogicValue.ofString('0100')[-2]; // == LogicValue.one
  /// LogicValue.ofString('0101')[-5]; // Error - out of range
  /// LogicValue.ofString('0101')[10]; // Error - out of range
  /// ```
  ///
  LogicValue operator [](int index) {
    final modifiedIndex = (index < 0) ? width + index : index;
    if (modifiedIndex >= width || modifiedIndex < 0) {
      // The suggestion in the deprecation for this constructor is not available
      // before 2.19, so keep it in here for now.  Eventually, switch to the
      // new one.
      // ignore: deprecated_member_use
      throw IndexError(index, this, 'LogicValueIndexOutOfRange',
          'Index out of range: $modifiedIndex(=$index).', width);
    }
    return _getIndex(modifiedIndex);
  }

  /// Returns the `i`th bit of this [LogicValue].  Performs no boundary checks.
  LogicValue _getIndex(int index);

  /// Returns a new [LogicValue] with the order of all bits in the reverse order
  /// of this [LogicValue]
  LogicValue get reversed;

  /// Returns a subset [LogicValue].  It is inclusive of [startIndex], exclusive
  /// of [endIndex].
  ///
  /// [startIndex] must come before the [endIndex] on position. If [startIndex]
  /// and [endIndex] are equal, then a zero-width value is returned.
  /// Both negative and positive index values are allowed. Negative indexing
  /// starts from the end=[width]-1.
  ///
  /// If [endIndex] is not provided, [width] of the [LogicValue] will
  /// be used as the default values which assign it to the last index.
  ///
  /// ```dart
  /// LogicValue.ofString('0101').getRange(0, 2);  // LogicValue.ofString('01')
  /// LogicValue.ofString('0101').getRange(1, -2); // LogicValue.zero
  /// LogicValue.ofString('0101').getRange(-3, 4); // LogicValue.ofString('010')
  /// LogicValue.ofString('0101').getRange(1);     // LogicValue.ofString('010')
  ///
  /// // Error - negative end index and start > end! start must be less than end
  /// LogicValue.ofString('0101').getRange(-1, -2);
  ///
  /// // Error - bad inputs start > end
  /// LogicValue.ofString('0101').getRange(2, 1);
  ///
  /// // Error - bad inputs end > length-1
  /// LogicValue.ofString('0101').getRange(0, 7);
  /// ```
  ///
  LogicValue getRange(int startIndex, [int? endIndex]) {
    endIndex ??= width;
    final modifiedStartIndex =
        (startIndex < 0) ? width + startIndex : startIndex;
    final modifiedEndIndex = (endIndex < 0) ? width + endIndex : endIndex;
    if (modifiedEndIndex < modifiedStartIndex) {
      throw Exception(
          'End $modifiedEndIndex(=$endIndex) cannot be less than start '
          '$modifiedStartIndex(=$startIndex).');
    }
    if (modifiedEndIndex > width) {
      throw Exception(
          'End $modifiedEndIndex(=$endIndex) must be less than width'
          ' ($width).');
    }
    if (modifiedStartIndex < 0) {
      throw Exception(
          'Start $modifiedStartIndex(=$startIndex) must be greater than or '
          'equal to 0.');
    }
    return _getRange(modifiedStartIndex, modifiedEndIndex);
  }

  /// Returns a subset [LogicValue].  It is inclusive of [start], exclusive of
  /// [end]. Performs no boundary checks.
  ///
  /// If [start] and [end] are equal, then a zero-width signal is returned.
  LogicValue _getRange(int start, int end);

  /// Accesses a subset of this [LogicValue] from [startIndex] to [endIndex],
  /// both inclusive.
  ///
  /// If [endIndex] is less than [startIndex], the returned value will be
  /// reversed relative to the original value.
  ///
  /// ```dart
  /// LogicValue.ofString('xz01').slice(2, 1);    // LogicValue.ofString('z0')
  /// LogicValue.ofString('xz01').slice(-2, -3);  // LogicValue.ofString('z0')
  /// LogicValue.ofString('xz01').slice(1, 3);    // LogicValue.ofString('0zx')
  /// LogicValue.ofString('xz01').slice(-3, -1);  // LogicValue.ofString('0zx')
  /// LogicValue.ofString('xz01').slice(-2, -2);  // LogicValue.ofString('z')
  /// ```
  LogicValue slice(int endIndex, int startIndex) {
    final modifiedStartIndex =
        (startIndex < 0) ? width + startIndex : startIndex;
    final modifiedEndIndex = (endIndex < 0) ? width + endIndex : endIndex;
    if (modifiedStartIndex <= modifiedEndIndex) {
      return getRange(modifiedStartIndex, modifiedEndIndex + 1);
    } else {
      return getRange(modifiedEndIndex, modifiedStartIndex + 1).reversed;
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
  // ignore: avoid_returning_this
  LogicValue get bit {
    if (width != 1) {
      throw Exception('Width must be 1, but was $width.');
    }
    // ignore: avoid_returning_this
    return this;
  }

  /// Converts valid a [LogicValue] to an [int].
  ///
  /// Throws an `Exception` if not [isValid] or the width doesn't fit in
  /// an [int].
  int toInt();

  /// Converts valid a [LogicValue] to an [int].
  ///
  /// Throws an `Exception` if not [isValid].
  BigInt toBigInt();

  /// Converts a valid logical value to a boolean.
  ///
  /// Throws an exception if the value is invalid.
  bool toBool() {
    if (!isValid) {
      throw Exception('Cannot convert value "$this" to bool');
    }
    if (width != 1) {
      throw Exception('Only single bit values can be converted to a bool,'
          ' but found width $width in $this');
    }
    return this == LogicValue.one;
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
  // ignore: avoid_dynamic_calls
  LogicValue operator +(dynamic other) => _doMath(other, (a, b) => a + b);

  /// Subtraction operation.
  ///
  /// WARNING: Signed math is not fully tested.
  // ignore: avoid_dynamic_calls
  LogicValue operator -(dynamic other) => _doMath(other, (a, b) => a - b);

  /// Multiplication operation.
  ///
  /// WARNING: Signed math is not fully tested.
  // ignore: avoid_dynamic_calls
  LogicValue operator *(dynamic other) => _doMath(other, (a, b) => a * b);

  /// Division operation.
  ///
  /// WARNING: Signed math is not fully tested.
  // ignore: avoid_dynamic_calls
  LogicValue operator /(dynamic other) => _doMath(other, (a, b) => a ~/ b);

  /// Modulo operation.
  ///
  // ignore: avoid_dynamic_calls
  LogicValue operator %(dynamic other) => _doMath(other, (a, b) => a % b);

  /// Executes mathematical operations between two [LogicValue]s
  ///
  /// Handles width and bounds checks as well as proper conversion between
  /// different types of representation.
  LogicValue _doMath(dynamic other, dynamic Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw Exception('Improper argument ${other.runtimeType}, should be int,'
          ' LogicValue, or BigInt.');
    }
    if (other is LogicValue && other.width != width) {
      throw Exception('Widths  must match, but found "$this" and "$other".');
    }

    if (!isValid) {
      return LogicValue.filled(width, LogicValue.x);
    }
    if (other is LogicValue && !other.isValid) {
      return LogicValue.filled(other.width, LogicValue.x);
    }

    if (this is _BigLogicValue || other is BigInt || other is _BigLogicValue) {
      final a = toBigInt();
      final b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other)
              : other is LogicValue
                  ? other.toBigInt()
                  : throw Exception(
                      'Unexpected big type: ${other.runtimeType}.');
      return LogicValue.ofBigInt(op(a, b) as BigInt, width);
    } else {
      final a = toInt();
      final b = other is int ? other : (other as LogicValue).toInt();
      return LogicValue.ofInt(op(a, b) as int, width);
    }
  }

  /// Equal-to operation.
  ///
  /// This is different from [==] because it returns a [LogicValue] instead
  /// of a [bool].  It does a logical comparison of the two values, rather
  /// than exact equality.  For example, if one of the two values is invalid,
  /// [eq] will return `x`.
  LogicValue eq(dynamic other) => _doCompare(other, (a, b) => a == b);

  /// Less-than operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator <(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a < b) as bool);

  /// Greater-than operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator >(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a > b) as bool);

  /// Less-than-or-equal operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator <=(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a <= b) as bool);

  /// Greater-than-or-equal operation.
  ///
  /// WARNING: Signed math is not fully tested.
  LogicValue operator >=(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a >= b) as bool);

  /// Executes comparison operations between two [LogicValue]s
  ///
  /// Handles width and bounds checks as well as proper conversion between
  /// different types of representation.
  LogicValue _doCompare(dynamic other, bool Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw Exception('Improper arguments ${other.runtimeType},'
          ' should be int, LogicValue, or BigInt.');
    }
    if (other is LogicValue && other.width != width) {
      throw Exception('Widths must match, but found "$this" and "$other"');
    }

    if (!isValid) {
      return LogicValue.x;
    }
    if (other is LogicValue && !other.isValid) {
      return LogicValue.x;
    }

    dynamic a;
    dynamic b;
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
    if (width == 0) {
      // ignore: avoid_returning_this
      return this;
    }
    int shamtInt;
    if (shamt is LogicValue) {
      if (!shamt.isValid) {
        return LogicValue.filled(width, LogicValue.x);
      }
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
  /// Only returns true from 0 -> 1.  If [previousValue] or [newValue] is
  /// invalid, an Exception will be thrown, unless [ignoreInvalid] is set
  /// to `true`.
  static bool isPosedge(LogicValue previousValue, LogicValue newValue,
      {bool ignoreInvalid = false}) {
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
  /// Only returns true from 1 -> 0.  If [previousValue] or [newValue] is
  /// invalid, an Exception will be thrown, unless [ignoreInvalid] is set
  /// to `true`.
  static bool isNegedge(LogicValue previousValue, LogicValue newValue,
      {bool ignoreInvalid = false}) {
    _assertSingleBit(previousValue);
    _assertSingleBit(newValue);

    if (!ignoreInvalid && (!previousValue.isValid | !newValue.isValid)) {
      throw Exception(
          'Edge detection on invalid value from $previousValue to $newValue');
    }
    return previousValue == LogicValue.one && newValue == LogicValue.zero;
  }

  /// Returns a new [LogicValue] with width [newWidth] where the most
  /// significant bits for indices beyond the original [width] are set
  /// to [fill].
  ///
  /// The [newWidth] must be greater than or equal to the current width or an
  /// exception will be thrown. [fill] must be a single bit ([width]=1).
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

  /// Returns a new [LogicValue] with width [newWidth] where new bits added are
  /// zeros as the most significant bits.
  ///
  /// The [newWidth] must be greater than or equal to the current width or an
  /// exception will be thrown.
  LogicValue zeroExtend(int newWidth) => extend(newWidth, LogicValue.zero);

  /// Returns a new [LogicValue] with width [newWidth] where new bits added are
  /// sign bits as the most significant bits.  The sign is determined using
  /// two's complement, so it takes the most significant bit of the original
  /// value and extends with that.
  ///
  /// The [newWidth] must be greater than or equal to the current width or an
  /// exception will be thrown.
  LogicValue signExtend(int newWidth) => extend(newWidth, this[width - 1]);

  /// Returns a copy of this [LogicValue] with the bits starting from
  /// [startIndex] up until [startIndex] + [update]`.width` set to [update]
  /// instead of their original value.
  ///
  /// The return value will be the same [width].  An exception will be thrown if
  /// the position of the [update] would cause an overrun past the [width].
  LogicValue withSet(int startIndex, LogicValue update) {
    if (startIndex + update.width > width) {
      throw Exception(
          'Width of updatedValue $update at startIndex $startIndex would'
          ' overrun the width of the original ($width).');
    }

    return [
      getRange(startIndex + update.width, width),
      update,
      getRange(0, startIndex),
    ].swizzle();
  }

  /// Checks if `this` is equal to [other], except ignoring bits of
  /// which are not valid.
  ///
  /// Returns `true` if each bit of `this` which [isValid] is equal
  /// to each bit of [other] which [isValid].
  ///
  /// For example:
  /// ```dart
  /// // Returns false
  /// LogicValue.ofString('1010xz').equalsWithDontCare(
  ///   LogicValue.ofString('10111x'));
  ///
  /// // Returns true
  /// LogicValue.ofString('10x111').equalsWithDontCare(
  ///   LogicValue.ofString('10111x'));
  ///
  /// // Returns false
  /// LogicValue.ofString('10x1z1').equalsWithDontCare(
  ///   LogicValue.ofString('10101x'));
  /// ```
  bool equalsWithDontCare(LogicValue other) {
    if (width == other.width) {
      for (var i = 0; i < width; i++) {
        if (!this[i].isValid || !other[i].isValid) {
          continue;
        } else if (this[i] != other[i]) {
          return false;
        }
      }
      return true;
    } else {
      return false;
    }
  }

  /// Returns new [LogicValue] replicated [multiplier] times. An exception will
  /// be thrown in case the multiplier is <1
  LogicValue replicate(int multiplier) {
    if (multiplier < 1) {
      throw InvalidMultiplierException(multiplier);
    }

    return LogicValue.of(List.filled(multiplier, this));
  }
}

/// Enum for direction of shift
enum _ShiftType { left, right, arithmeticRight }

/// Converts a binary [String] representation to a binary [int].
///
/// Ignores all '_' in the provided binary.
int bin(String s) => _unsignedBinaryParse(s.replaceAll('_', ''));

/// Parses [source] as a binary integer, similarly to [int.parse].
///
/// If [source] interpreted as a positive signed integer would be larger than
/// the maximum allowed by [int], then [int.parse] will throw an exception. This
/// function will instead properly interpret it as an unsigned integer.
int _unsignedBinaryParse(String source) {
  final val = int.tryParse(source, radix: 2);
  if (val != null) {
    return val;
  } else {
    return BigInt.parse(source, radix: 2).toIntUnsigned(source.length);
  }
}

/// Enum for a [LogicValue]'s value.
enum _LogicValueEnum { zero, one, x, z }
