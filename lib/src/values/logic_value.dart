// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_values.dart
// Definitions for a set of logical values of any width
//
// 2021 August 2
// Author: Max Korbel <max.korbel@intel.com>

part of 'values.dart';

/// Deprecated: use [LogicValue] instead.
@Deprecated('Use `LogicValue` instead.'
    '  `LogicValues` and `LogicValue` have been merged into one type.')
typedef LogicValues = LogicValue;

/// An immutable 4-value representation of an arbitrary number of bits.
///
/// Each bit of [LogicValue] can be represented as a [LogicValue]
/// of `0`, `1`, `x` (contention), or `z` (floating).
///
/// [LogicValue] is unsigned.
@immutable
abstract class LogicValue implements Comparable<LogicValue> {
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
  static LogicValue ofInt(int value, int width) => width > INT_BITS
      ? _bigLogicValueOrFilled(
          BigInt.from(value).toUnsigned(INT_BITS), BigInt.zero, width)
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
  static LogicValue ofBigInt(BigInt value, int width) => width > INT_BITS
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
  /// [width] must be greater than or equal to 0.  [fill] must be 1 bit.
  static LogicValue filled(int width, LogicValue fill) =>
      _FilledLogicValue(fill._enum, width);

  /// Gets the [_LogicValueEnum] for single-bit [LogicValue]s.
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
                    : throw LogicValueConversionException('Failed to convert.');
  }

  /// Creates a [LogicValue] of [val] using [of], but attempts to infer the
  /// width that would fit [val] automatically.
  ///
  /// Only accepts [val]s of types [int], [BigInt], and [LogicValue].
  ///
  /// The width of negative numbers cannot be inferred and an exception will
  /// be thrown.
  static LogicValue ofInferWidth(dynamic val) {
    int width;
    if (val is int) {
      if (val < 0) {
        throw LogicValueConstructionException(
            'Cannot infer width of a negative int.');
      } else {
        width = val.bitLength;
      }
    } else if (val is BigInt) {
      if (val.isNegative) {
        throw LogicValueConstructionException(
            'Cannot infer width of a negative BigInt.');
      } else {
        width = val.bitLength;
      }
    } else if (val is LogicValue) {
      width = val.width;
    } else {
      throw UnsupportedTypeException(val, const [int, BigInt, LogicValue]);
    }

    return LogicValue.of(val, width: width);
  }

  /// Constructs a [LogicValue] from [val] which could be of a variety of types.
  ///
  /// Supported types include [String], [bool], [int], [BigInt], [LogicValue],
  /// and [Iterable<LogicValue>].
  ///
  /// If [fill] is set, then all bits of the returned value will be set to
  /// [val]. If the [val] is not representable as a single bit of information,
  /// then setting [fill] will throw an [Exception].
  ///
  /// If the [width] can be inferred from the type (e.g. [String], [LogicValue],
  /// [Iterable<LogicValue>]), then [width] does not need to be provided.
  /// If [width] is provided and does not match an inferred width, then [width]
  /// is used.
  /// If a [width] cannot be inferred, then it is required, or else it will
  /// throw an [Exception].
  /// If [val] does not fit in a specified [width], then the returned value will
  /// be truncated.
  /// [bool]s will infer a default width of `1`, but it can be overridden.
  /// Invalid 1-bit [val]s will always be [fill]ed even if [fill] is `false`,
  /// but will default to a width of 1 unless [width] is specified.
  static LogicValue of(dynamic val, {bool fill = false, int? width}) {
    if (val is int) {
      if (width == null) {
        throw LogicValueConstructionException(
            '`width` must be provided for `int`.');
      }

      if (fill) {
        return LogicValue.filled(
            width,
            val == 0
                ? LogicValue.zero
                : val == 1
                    ? LogicValue.one
                    : throw LogicValueConstructionException(
                        '`int` can only can fill 0 or 1, but saw $val.'));
      } else {
        return LogicValue.ofInt(val, width);
      }
    } else if (val is BigInt) {
      if (width == null) {
        throw LogicValueConstructionException(
            '`width` must be provided for `BigInt`.');
      }

      if (fill) {
        return LogicValue.filled(
            width,
            val == BigInt.zero
                ? LogicValue.zero
                : val == BigInt.one
                    ? LogicValue.one
                    : throw LogicValueConstructionException(
                        '`BigInt` can only fill 0 or 1, but saw $val.'));
      } else {
        return LogicValue.ofBigInt(val, width);
      }
    } else if (val is bool) {
      width ??= 1;

      if (fill) {
        return LogicValue.filled(width, val ? LogicValue.one : LogicValue.zero);
      }
      return LogicValue.ofInt(val ? 1 : 0, width);
    } else if (val is LogicValue) {
      if (fill && val.width != 1) {
        throw LogicValueConstructionException(
            'Only 1-bit `LogicValue`s can be filled');
      }

      if (val.width == 1 && (!val.isValid || fill)) {
        if (!val.isValid) {
          // ignore: parameter_assignments
          width ??= 1;
        }
        if (width == null) {
          throw LogicValueConstructionException(
              'Filled `LogicValue` $val must have provided a width.');
        }
        return LogicValue.filled(width, val);
      } else {
        if (val.width == width || width == null) {
          return val;
        } else if (width < val.width) {
          return val.getRange(0, width);
        } else {
          return val.zeroExtend(width);
        }
      }
    } else if (val is String) {
      if (fill && val.length != 1) {
        throw LogicValueConstructionException(
            'Only 1-bit values can be filled');
      }

      if (val.length == 1 && (val == 'x' || val == 'z' || fill)) {
        if (val == 'x' || val == 'z') {
          // ignore: parameter_assignments
          width ??= 1;
        }
        if (width == null) {
          throw LogicValueConstructionException(
              'Filled `String` $val must have provided a width.');
        }
        return LogicValue.filled(width, LogicValue.ofString(val));
      } else {
        if (val.length == width || width == null) {
          return LogicValue.ofString(val);
        } else if (width < val.length) {
          return LogicValue.ofString(val.substring(0, width));
        } else {
          return LogicValue.ofString(val).zeroExtend(width);
        }
      }
    } else if (val is Iterable<LogicValue>) {
      if (fill && val.length != 1) {
        throw LogicValueConstructionException(
            'Only 1-bit values can be filled');
      }

      if (val.length == 1 &&
          (val.first == LogicValue.x || val.first == LogicValue.z || fill)) {
        if (!val.first.isValid) {
          // ignore: parameter_assignments
          width ??= 1;
        }
        if (width == null) {
          throw LogicValueConstructionException(
              'Filled `Iterable<LogicValue>` $val must have provided a width.');
        }
        return LogicValue.filled(width, val.first);
      } else {
        if (val.length == width || width == null) {
          return LogicValue.ofIterable(val);
        } else if (width < val.length) {
          return LogicValue.ofIterable(val).getRange(0, width);
        } else {
          return LogicValue.ofIterable(val).zeroExtend(width);
        }
      }
    } else if (val == null) {
      throw LogicValueConstructionException('Cannot construct from `null`.');
    } else {
      throw UnsupportedTypeException(val,
          const [LogicValue, int, BigInt, bool, String, Iterable<LogicValue>]);
    }
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
  static LogicValue ofIterable(Iterable<LogicValue> it) {
    var smallBuffer = LogicValue.empty;
    var fullResult = LogicValue.empty;

    // shift small chunks in together before shifting BigInt's, since
    // shifting BigInt's is expensive
    for (final lv in it) {
      final lvPlusSmall = lv.width + smallBuffer.width;
      if (lvPlusSmall <= INT_BITS) {
        smallBuffer = lv._concatenate(smallBuffer);
      } else {
        // only put 64-bit chunks onto `fullResult`, rest onto `smallBuffer`
        final upperBound =
            INT_BITS * (lvPlusSmall ~/ INT_BITS) - smallBuffer.width;
        fullResult = lv
            .getRange(0, upperBound)
            ._concatenate(smallBuffer)
            ._concatenate(fullResult);
        smallBuffer = lv.getRange(upperBound, lv.width);
      }

      assert(smallBuffer.width <= INT_BITS,
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
    } else if (newWidth > INT_BITS) {
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
  static LogicValue from(Iterable<LogicValue> it) => ofIterable(it);

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
      (x ^ _SmallLogicValue._maskOfWidth(width)) &
          _SmallLogicValue._maskOfWidth(width) ==
      0;

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

    if (stringRepresentation.contains(RegExp('[^01xz]'))) {
      throw LogicValueConstructionException(
          'Invalid characters found, must only contain 0, 1, x, and z.');
    }

    final valueString = _valueString(stringRepresentation);
    final invalidString = _invalidString(stringRepresentation);
    final width = stringRepresentation.length;

    if (width <= INT_BITS) {
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
  /// Only use if [width] > [INT_BITS].
  static LogicValue _bigLogicValueOrFilled(
      BigInt value, BigInt invalid, int width) {
    assert(width > INT_BITS, 'Should only be used for big values');

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
  /// Only use if [width] <= [INT_BITS].
  static LogicValue _smallLogicValueOrFilled(
      int value, int invalid, int width) {
    assert(width <= INT_BITS, 'Should only be used for small values');

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
      List<LogicValue>.generate(width, (index) => this[index])
          .toList(growable: false);

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
      // for ==INT_BITS, still use BigInt so we don't get negatives
      final hexValue = width >= INT_BITS
          ? toBigInt().toUnsigned(width).toRadixString(16)
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

  /// Legal characters in a radixString representation.
  static const String radixStringChars = "'0123456789aAbBcCdDeEfFqohzZxX";

  /// Reverse a string (helper function)
  static String _reverse(String inString) =>
      String.fromCharCodes(inString.runes.toList().reversed);

  /// Return the radix encoding of the current [LogicValue] as a sequence
  /// of radix characters prefixed by the length and encoding format.
  /// Output format is: `<len>'<format><encoded-value>`.
  ///
  /// [ofRadixString] can parse a [String] produced by [toRadixString] and
  /// construct a [LogicValue].
  ///
  /// Here is the number 1492 printed as a radix string:
  /// - Binary: `15'b101_1101_0100`
  /// - Quaternary: `15'q11_3110`
  /// - Octal: `15'o2724`
  /// - Decimal: `10'd1492`
  /// - Hex: `15'h05d4`
  ///
  /// Separators are output according to [chunkSize] starting from the
  /// LSB(right), default is 4 characters.  The default separator is '_'.
  /// [sepChar] can be set to another character, but not in [radixStringChars],
  /// otherwise it will throw an exception.
  ///  - [chunkSize] = default: `61'h2_9ebc_5f06_5bf7`
  ///  - [chunkSize] = 10: `61'h29e_bc5f065bf7`
  ///
  /// [leadingZeros] defaults to false, so leading 0s are omitted in
  /// the output string:
  /// - `25'h1`
  /// otherwise if [leadingZeros] is set to true then the output string is:
  /// - `25'h000_0001`
  ///
  /// When a [LogicValue] has 'x' or 'z' bits, then the radix characters those
  /// bits overlap will be expanded into binary form with '<' '>' bracketing
  /// them as follows:
  ///   - `35'h7_ZZZZ_Z<zzz0><100z>Z`
  /// Such a [LogicValue] cannot be converted to a Decimal (10) radix string
  /// and will throw an exception.
  ///
  /// If the leading bits are 'z', then the output radix character is 'Z' no
  /// matter what the length. When leading, 'Z' indicates one or more 'z'
  /// bits to fill the first radix character.
  /// - `9'bz_zzzz_zzzz = 9'hZZZ`
  ///
  String toRadixString(
      {int radix = 2,
      int chunkSize = 4,
      bool leadingZeros = false,
      String sepChar = '_'}) {
    if (radixStringChars.contains(sepChar)) {
      throw LogicValueConversionException('separation character invalid');
    }
    final radixStr = switch (radix) {
      2 => "'b",
      4 => "'q",
      8 => "'o",
      10 => "'d",
      16 => "'h",
      _ => throw LogicValueConversionException('Unsupported radix: $radix')
    };
    final String reversedStr;
    if (radix == 10) {
      if (isValid) {
        var radixString =
            toBigInt().toUnsigned(width).toRadixString(radix).toUpperCase();
        if (leadingZeros) {
          final span =
              math.max(1, (width * math.log(2) / math.log(radix)).floor());
          for (var i = radixString.length; i < (width / span).ceil(); i++) {
            radixString = '0$radixString';
          }
        }
        reversedStr = _reverse(radixString);
      } else {
        final span =
            math.max(1, (width * math.log(2) / math.log(radix)).floor());
        if (toRadixString().contains(RegExp('[xX]'))) {
          reversedStr = 'X' * span;
        } else {
          reversedStr = 'Z' * span;
        }
      }
    } else {
      final span = (math.log(radix) / math.log(2)).ceil();
      final extendedStr =
          LogicValue.of(this, width: span * (width / span).ceil());
      final buf = StringBuffer();
      var haveLeadingZeros = true;
      for (var i = (extendedStr.width ~/ span) - 1; i >= 0; i--) {
        final binaryChunk = extendedStr.slice((i + 1) * span - 1, i * span);
        var chunkString = binaryChunk.toString(includeWidth: false);
        if (i == extendedStr.width ~/ span - 1) {
          final chunkWidth = chunkString.length;
          chunkString = chunkString.substring(
              chunkWidth - (width - i * span), chunkWidth);
        }
        final s = [
          if (chunkString == 'z' * chunkString.length)
            (span == 1 ? 'z' : 'Z')
          else if (chunkString == 'x' * chunkString.length)
            (span == 1 ? 'x' : 'X')
          else if (chunkString.contains('z') | chunkString.contains('x'))
            '>${_reverse(chunkString)}<'
          else
            binaryChunk.toBigInt().toUnsigned(span).toRadixString(radix)
        ].first;
        if (s != '0') {
          haveLeadingZeros = false;
        }
        if ((s == '0') & !leadingZeros & haveLeadingZeros) {
          continue;
        }
        buf.write(_reverse(s));
      }
      reversedStr = _reverse(buf.toString());
    }

    final spaceString = _reverse(reversedStr
        .replaceAllMapped(
            RegExp('((>(.){$chunkSize}<)|([a-zA-Z0-9])){$chunkSize}'),
            (match) => '${match.group(0)}$sepChar')
        .replaceAll('$sepChar<', '<'));

    final fullString = (spaceString.isNotEmpty)
        ? (spaceString[0] == sepChar)
            ? spaceString.substring(1, spaceString.length)
            : spaceString
        : '0';
    return '$width$radixStr$fullString';
  }

  /// Create a [LogicValue] from a length/radix-encoded string of the
  /// following format:
  ///
  ///  `<length><format><value-string>`.
  ///
  /// `<length>` is the binary digit length of the [LogicValue] to be
  /// constructed.
  ///
  /// `<format>s`  supported are `'b,'q,'o,'d,'h` supporting radixes as follows:
  ///  - 'b: binary (radix 2)
  ///  - 'q: quaternary (radix 4)
  ///  - 'o: octal (radix 8)
  ///  - 'd: decimal (radix 10)
  ///  - 'h: hexadecimal (radix 16)
  ///
  /// `<value-string>` contains space-separated digits corresponding to the
  /// radix format.  Space-separation is for ease of reading and is often
  /// in chunks of 4 digits.
  ///
  /// If the format of then length/radix-encoded string is not completely parsed
  /// an exception will be thrown.  This can be caused by illegal characters
  /// in the string or too long of a value string.
  ///
  ///  Strings created by [toRadixString] are parsed by [ofRadixString].
  ///
  /// If the LogicValue width is not encoded as round number of radix
  /// characters, the leading character must be small enough to be encoded
  /// in the remaining width:
  ///  - 9'h1aa
  ///  - 10'h2aa
  ///  - 11'h4aa
  ///  - 12'haa
  static LogicValue ofRadixString(String valueString, {String sepChar = '_'}) {
    if (radixStringChars.contains(sepChar)) {
      throw LogicValueConstructionException('separation character invalid');
    }
    if (RegExp(r'^\d+').firstMatch(valueString) != null) {
      final formatStr =
          RegExp("^(\\d+)'([bqodh])([0-9aAbBcCdDeEfFzZxX<>$sepChar]*)")
              .firstMatch(valueString);
      if (formatStr != null) {
        if (valueString.length != formatStr.group(0)!.length) {
          throw LogicValueConstructionException('radix string stopped '
              'parsing at character position ${formatStr.group(0)!.length}');
        }
        final specifiedLength = int.parse(formatStr.group(1)!);
        final compressedStr = formatStr.group(3)!.replaceAll(sepChar, '');
        // Extract radix
        final radixString = formatStr.group(2)!;
        final radix = switch (radixString) {
          'b' => 2,
          'q' => 4,
          'o' => 8,
          'd' => 10,
          'h' => 16,
          _ => throw LogicValueConstructionException(
              'Unsupported radix: $radixString'),
        };
        final span = (math.log(radix) / math.log(2)).ceil();

        final reversedStr = _reverse(compressedStr);
        // Find any binary expansions, then extend to the span
        final binaries = RegExp('>[^<>]*<').allMatches(reversedStr).indexed;

        // At this point, binaryLength has the binary bit count for binaries
        // Remove and store expansions of binary fields '<[x0z1]*>.
        final fullBinaries = RegExp('>[^<>]*<');
        final bitExpandLocs = fullBinaries.allMatches(reversedStr).indexed;

        final numExpanded = bitExpandLocs.length;
        final numChars = reversedStr.length - numExpanded * (span + 1);
        final binaryLength = (binaries.isEmpty
                ? 0
                : binaries
                    .map<int>((j) => j.$2.group(0)!.length - 2)
                    .reduce((a, b) => a + b)) +
            (numChars - numExpanded) * span;

        // is the binary length shorter than it appears
        final int shorter;
        if ((binaries.isNotEmpty) && compressedStr[0] == '<') {
          final binGroup = _reverse(binaries.last.$2.group(0)!);
          final binaryChunk = binGroup.substring(1, binGroup.length - 1);
          var cnt = 0;
          while (cnt < binaryChunk.length - 1 && binaryChunk[cnt++] == '0') {}
          shorter = cnt - 1;
        } else {
          if (compressedStr.isNotEmpty) {
            final leadChar = compressedStr[0];
            if (RegExp('[xXzZ]').hasMatch(leadChar)) {
              shorter = span - 1;
            } else {
              shorter = span -
                  BigInt.parse(leadChar, radix: radix).toRadixString(2).length;
            }
          } else {
            shorter = 0;
          }
        }
        if ((radix != 10) & (binaryLength - shorter > specifiedLength)) {
          throw LogicValueConstructionException(
              'ofRadixString: cannot represent '
              '$compressedStr in $specifiedLength');
        }
        final noBinariesStr = reversedStr.replaceAll(fullBinaries, '0');
        final xLocations = RegExp('x|X')
            .allMatches(noBinariesStr)
            .indexed
            .map((m) => List.generate(span, (s) => m.$2.start * span + s))
            .expand((xe) => xe);
        final zLocations = RegExp('z|Z')
            .allMatches(noBinariesStr)
            .indexed
            .map((m) => List.generate(span, (s) => m.$2.start * span + s))
            .expand((ze) => ze);

        final BigInt intValue;
        if (noBinariesStr.isNotEmpty) {
          intValue = BigInt.parse(
                  _reverse(noBinariesStr.replaceAll(RegExp('[xXzZ]'), '0')),
                  radix: radix)
              .toUnsigned(specifiedLength);
        } else {
          intValue = BigInt.zero;
        }
        final logicValList = List<LogicValue>.from(
            LogicValue.ofString(intValue.toRadixString(2))
                .zeroExtend(specifiedLength)
                .toList());
        // Put all the X and Z's back into the list
        for (final x in xLocations) {
          if (x < specifiedLength) {
            logicValList[x] = LogicValue.x;
          }
        }
        for (final z in zLocations) {
          if (z < specifiedLength) {
            logicValList[z] = LogicValue.z;
          }
        }

        // Now add back the bitfield expansions stored earlier
        var lastPos = 0;
        var lastCpos = 0;
        for (final i in bitExpandLocs) {
          var len = i.$2.group(0)!.length;
          if (i.$1 == bitExpandLocs.last.$1) {
            final revBitChars = i.$2.group(0)!;
            while (len > 1 && revBitChars[len - 2] == '0') {
              len--;
            }
          }
          final bitChars = i.$2.group(0)!.substring(1, len - 1);
          var pos = 0;
          if (i.$1 > 0) {
            final nonExpChars = i.$2.start - lastCpos - span - 2;
            pos = lastPos + span + span * nonExpChars;
          } else {
            final nonExpChars = i.$2.start - lastCpos;
            pos = lastPos + span * nonExpChars;
          }

          for (var bitPos = 0; bitPos < len - 2; bitPos++) {
            logicValList[pos + bitPos] = switch (bitChars[bitPos]) {
              '0' => LogicValue.zero,
              '1' => LogicValue.one,
              'x' => LogicValue.x,
              _ => LogicValue.z
            };
          }
          lastCpos = i.$2.start;
          lastPos = pos;
        }
        return logicValList.rswizzle();
      } else {
        throw LogicValueConstructionException(
            'Invalid LogicValue string $valueString');
      }
    }
    return LogicValue.zero;
  }

  /// Compares this to `other`.
  ///
  /// Returns a negative number if `this` is less than `other`, zero if they are
  /// equal, and a positive number if `this` is greater than `other`.
  ///
  /// It will throw an exception if `this` or [other] is not [isValid] or for
  /// non-equal `LogicValue` [width].
  @override
  int compareTo(Object other) {
    if (other is! LogicValue) {
      throw Exception('Input must be of type LogicValue ');
    }

    if (!isValid) {
      throw InvalidValueOperationException(this, 'Comparison');
    }

    if (!other.isValid) {
      throw InvalidValueOperationException(other, 'Comparison');
    }

    if (other.width != width) {
      throw ValueWidthMismatchException(this, other);
    }

    if (width > INT_BITS || other.width > INT_BITS) {
      final a = toBigInt();
      final b = other.toBigInt();
      final valueZero = BigInt.zero;

      if ((a < valueZero && b < valueZero) ||
          (a >= valueZero && b >= valueZero)) {
        return a.compareTo(b);
      } else if (a < valueZero && b >= valueZero) {
        return 1;
      } else {
        return -1;
      }
    } else {
      final a = toInt();
      final b = other.toInt();
      const valueZero = 0;

      if ((a < valueZero && b < valueZero) ||
          (a >= valueZero && b >= valueZero)) {
        return a.compareTo(b);
      } else if (a < valueZero && b >= valueZero) {
        return 1;
      } else {
        return -1;
      }
    }
  }

  String _bitString() {
    if (width != 1) {
      throw LogicValueConversionException(
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
    final modifiedIndex = IndexUtilities.wrapIndex(index, width);

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
        IndexUtilities.wrapIndex(startIndex, width, allowWidth: true);
    final modifiedEndIndex =
        IndexUtilities.wrapIndex(endIndex, width, allowWidth: true);

    // if we're getting the whole thing, just return itself immediately
    if (modifiedStartIndex == 0 && modifiedEndIndex == width) {
      return this;
    }

    IndexUtilities.validateRange(modifiedStartIndex, modifiedEndIndex);

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
    final modifiedStartIndex = IndexUtilities.wrapIndex(startIndex, width);
    final modifiedEndIndex = IndexUtilities.wrapIndex(endIndex, width);

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
  /// Throws an `Exception` if not [isValid] or the value doesn't fit in
  /// an [int].
  int toInt();

  /// Converts valid a [LogicValue] to an [int].
  ///
  /// Throws an `Exception` if not [isValid].
  BigInt toBigInt();

  /// Converts a valid logical value to a boolean.
  ///
  /// Throws a LogicValueConversionException if the value is invalid.
  bool toBool() {
    if (!isValid) {
      throw LogicValueConversionException(
          'Cannot convert value "$this" to bool');
    }
    if (width != 1) {
      throw LogicValueConversionException(
          'Only single bit values can be converted to a bool,'
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

  /// Bitwise tristate merge of this value with [other].
  ///
  /// Per bit:
  /// - tristate(0, 0) == 0
  /// - tristate(0, 1) == x
  /// - tristate(0, x) == x
  /// - tristate(0, z) == 0
  /// - tristate(1, 1) == 1
  /// - tristate(1, x) == x
  /// - tristate(1, z) == 1
  /// - tristate(z, x) == x
  /// - tristate(z, z) == z
  /// - tristate(x, x) == x
  LogicValue triState(LogicValue other) =>
      _twoInputBitwiseOp(other, (a, b) => a._triState2(b));

  /// Bitwise AND operation.  No width comparison.
  LogicValue _and2(LogicValue other);

  /// Bitwise OR operation.  No width comparison.
  LogicValue _or2(LogicValue other);

  /// Bitwise XOR operation.  No width comparison.
  LogicValue _xor2(LogicValue other);

  /// Bitwise tristate merge.  No width comparison.
  ///
  /// Truth table for reference:
  /// ```csv
  /// s0	value0	invalid0	s1	value1	invalid1	result	value	invalid
  /// 0	0	0	0	0	0	0	0	0
  /// 0	0	0	1	1	0	x	0	1
  /// 0	0	0	x	0	1	x	0	1
  /// 0	0	0	z	1	1	0	0	0
  /// 1	1	0	1	1	0	1	1	0
  /// 1	1	0	x	0	1	x	0	1
  /// 1	1	0	z	1	1	1	1	0
  /// x	0	1	x	0	1	x	0	1
  /// z	1	1	x	0	1	x	0	1
  /// z	1	1	z	1	1	z	1	1
  /// ```
  LogicValue _triState2(LogicValue other);

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

  /// Calculates the absolute value, assuming that the
  /// number is a two's complement.
  LogicValue abs() {
    if (width == 0) {
      return this;
    }
    if (!this[-1].isValid) {
      return LogicValue.filled(width, LogicValue.x);
    }
    return this[-1] == LogicValue.one
        ? ~this + LogicValue.ofInt(1, width)
        : this;
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
  LogicValue operator +(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doMath(other, (a, b) => a + b);

  /// Subtraction operation.
  LogicValue operator -(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doMath(other, (a, b) => a - b);

  /// Multiplication operation.
  LogicValue operator *(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doMath(other, (a, b) => a * b);

  /// Division operation.
  LogicValue operator /(dynamic other) => _doMath(
        other,
        // ignore: avoid_dynamic_calls
        (a, b) => a ~/ b,
        isDivision: true,
      );

  /// Modulo operation.
  LogicValue operator %(dynamic other) => _doMath(
        other,
        // ignore: avoid_dynamic_calls
        (a, b) => a % b,
        isDivision: true,
      );

  /// Ceil of log base 2 operation.
  ///
  /// Returns ceil of log base 2 of valid input.
  /// Returns `x` if any bit of input is invalid.
  LogicValue clog2() => _doUnaryMath(_clog2);

  /// Executes mathematical operations on single [LogicValue]
  ///
  /// Handles invalid input and do proper type conversion to required types
  LogicValue _doUnaryMath(dynamic Function(dynamic a, int width) op) {
    if (!isValid) {
      return LogicValue.filled(width, LogicValue.x);
    }
    if (width > INT_BITS) {
      final a = toBigInt();
      return LogicValue.ofBigInt(op(a, width) as BigInt, width);
    } else {
      final a = toInt();
      return LogicValue.ofInt(op(a, width) as int, width);
    }
  }

  /// Ceil of log base 2 Operation
  ///
  /// Input [a] will be either of type [int] or [BigInt].
  /// Returns ceil of log base 2 of [a]  having same type as of input [a].
  static dynamic _clog2(dynamic a, int width) {
    if (a is int) {
      return a < 0
          ? (a << 1 == 0) // handle b100000... of INT_BITS width
              ? width - 1
              : width
          : (a - 1).bitLength;
    }

    if (a is BigInt) {
      assert(a >= BigInt.zero, 'Expected only positive BigInt here');
      return a < BigInt.zero
          ? (a << 1 == BigInt.zero)
              ? BigInt.from(width - 1)
              : BigInt.from(width)
          : BigInt.from((a - BigInt.one).bitLength);
    }
  }

  /// Executes mathematical operations between two [LogicValue]s.
  ///
  /// Handles width and bounds checks as well as proper conversion between
  /// different types of representation.
  ///
  /// If the math [isDivision], then 64-bit ([INT_BITS]) operations have some
  /// special consideration for two's complement math, so it will use an
  /// unsigned [BigInt] for math.
  LogicValue _doMath(dynamic other, dynamic Function(dynamic a, dynamic b) op,
      {bool isDivision = false}) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw UnsupportedTypeException(other, const [int, LogicValue, BigInt]);
    }

    if (other is LogicValue && other.width != width) {
      throw ValueWidthMismatchException(this, other);
    }

    if (!isValid) {
      return LogicValue.filled(width, LogicValue.x);
    }

    if (isDivision &&
        (other == 0 ||
            other == BigInt.zero ||
            (other is LogicValue && other.isZero))) {
      return LogicValue.filled(width, LogicValue.x);
    }

    if (other is LogicValue && !other.isValid) {
      return LogicValue.filled(other.width, LogicValue.x);
    }

    final widthComparison = isDivision ? INT_BITS - 1 : INT_BITS;

    if (width > widthComparison ||
        (other is LogicValue && other.width > widthComparison)) {
      final a = toBigInt();
      final b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other).toUnsigned(INT_BITS)
              : (other as LogicValue).toBigInt();
      return LogicValue.ofBigInt(op(a, b) as BigInt, width);
    } else {
      final a = toInt();
      final b = other is int ? other : (other as LogicValue).toInt();
      return LogicValue.ofInt(op(a, b) as int, width);
    }
  }

  /// Returns true if this value is `0`.
  bool get isZero;

  /// Equal-to operation.
  ///
  /// This is different from [==] because it returns a [LogicValue] instead
  /// of a [bool].  It does a logical comparison of the two values, rather
  /// than exact equality.  For example, if one of the two values is invalid,
  /// [eq] will return `x`.
  LogicValue eq(dynamic other) => _doCompare(other, (a, b) => a == b);

  /// Not equal-to operation.
  ///
  /// This is different from != operator because it returns a [LogicValue]
  /// instead of a [bool]. It does a logical comparison of the two values,
  /// rather than exact inequality.  For example, if one of the two values is
  /// invalid, [neq] will return `x`.
  LogicValue neq(dynamic other) => _doCompare(other, (a, b) => a != b);

  /// Power operation.
  ///
  /// This will return a [LogicValue] of some input 'base' to the power of other
  /// input [exponent]. If one of the two input values is invalid, [pow] will
  /// return ‘x’ of input size width.
  LogicValue pow(dynamic exponent) => _doMath(exponent, _powerOperation);

  /// Less-than operation.
  LogicValue operator <(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a < b) as bool);

  /// Greater-than operation.
  LogicValue operator >(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a > b) as bool);

  /// Less-than-or-equal operation.
  LogicValue operator <=(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a <= b) as bool);

  /// Greater-than-or-equal operation.
  LogicValue operator >=(dynamic other) =>
      // ignore: avoid_dynamic_calls
      _doCompare(other, (a, b) => (a >= b) as bool);

  /// Power operation.
  ///
  /// Both inputs [base] and [exponent] are either of type [int] or [BigInt].
  /// Returns [base] raise to the power [exponent] of same input type else
  /// it will throw an exception.
  dynamic _powerOperation(dynamic base, dynamic exponent) {
    if ((base is int) && (exponent is int)) {
      return math.pow(base, exponent);
    }
    if ((base is BigInt) && (exponent is BigInt)) {
      if (base == BigInt.one) {
        return BigInt.one;
      } else if (base == BigInt.zero && exponent > BigInt.zero) {
        return BigInt.zero;
      } else if (!exponent.isValidInt) {
        throw InvalidTruncationException(
            "BigInt (${exponent.bitLength} bits) won't fit in "
            'int ($INT_BITS bits)');
      } else {
        return base.pow(exponent.toInt());
      }
    }
  }

  /// Executes comparison operations between two [LogicValue]s.
  ///
  /// Handles width and bounds checks as well as proper conversion between
  /// different types of representation.
  LogicValue _doCompare(dynamic other, bool Function(dynamic a, dynamic b) op) {
    if (!(other is int || other is LogicValue || other is BigInt)) {
      throw UnsupportedTypeException(other, const [int, LogicValue, BigInt]);
    }

    if (other is LogicValue && other.width != width) {
      throw ValueWidthMismatchException(this, other);
    }

    if (!isValid) {
      return LogicValue.x;
    }
    if (other is LogicValue && !other.isValid) {
      return LogicValue.x;
    }

    dynamic a;
    dynamic b;
    if (width > INT_BITS || (other is LogicValue && other.width > INT_BITS)) {
      a = toBigInt();
      b = other is BigInt
          ? other
          : other is int
              ? BigInt.from(other).toUnsigned(INT_BITS)
              : (other as LogicValue).toBigInt();
    } else {
      if (width < INT_BITS) {
        a = toInt();
        b = other is int ? other : (other as LogicValue).toInt();
      } else {
        // Here we now know: width == INT_BITS
        final ai = toInt();
        final bi = other is int ? other : (other as LogicValue).toInt();

        if ((ai < 0) || (bi < 0)) {
          final abig = LogicValue.ofBigInt(BigInt.from(ai), INT_BITS + 1);
          final bbig = LogicValue.ofBigInt(BigInt.from(bi), INT_BITS + 1);
          return abig._doCompare(bbig, op);
        }

        a = ai;
        b = bi;
      }
    }

    return op(a, b) ? LogicValue.one : LogicValue.zero;
  }

  /// Arithmetic right-shift operation.
  ///
  /// Shifted in bits will match the sign (upper-most bit).
  LogicValue operator >>(dynamic shamt) =>
      _shift(shamt, _ShiftType.arithmeticRight);

  /// Logical left-shift operation.
  ///
  /// Shifted in bits are all 0.
  LogicValue operator <<(dynamic shamt) => _shift(shamt, _ShiftType.left);

  /// Logical right-shift operation.
  ///
  /// Shifted in bits are all 0.
  LogicValue operator >>>(dynamic shamt) => _shift(shamt, _ShiftType.right);

  /// Performs a shift by a huge amount (more than [width]).
  LogicValue _shiftHuge(_ShiftType direction) {
    if (direction == _ShiftType.arithmeticRight &&
        this[-1] != LogicValue.zero) {
      return LogicValue.filled(
          width, this[-1].isValid ? LogicValue.one : LogicValue.x);
    } else {
      return LogicValue.filled(width, LogicValue.zero);
    }
  }

  /// Performs shift operations in the specified direction
  LogicValue _shift(dynamic shamt, _ShiftType direction) {
    if (width == 0) {
      // ignore: avoid_returning_this
      return this;
    }

    var shamtNum = shamt;
    if (shamt is LogicValue) {
      if (!shamt.isValid) {
        return LogicValue.filled(width, LogicValue.x);
      }

      if (shamt.width > INT_BITS) {
        shamtNum = shamt.toBigInt();
      } else {
        shamtNum = shamt.toInt();
      }
    }

    int shamtInt;
    if (shamtNum is int) {
      shamtInt = shamtNum;
    } else if (shamtNum is BigInt) {
      if (shamtNum >= BigInt.from(width)) {
        // if the shift amount is huge, we can still calculate it
        return _shiftHuge(direction);
      }

      assert(
          shamtNum <= BigInt.from(-1).toUnsigned(INT_BITS),
          'It should not be possible for the shift amount to be less '
          'than the width, but more than fits in an int.');

      assert(shamtNum.isValidInt,
          'Should have returned already if it does not fit.');

      shamtInt = shamtNum.toInt();
    } else {
      throw UnsupportedTypeException(shamt, const [int, BigInt, LogicValue]);
    }

    if (shamtInt < 0) {
      // since we're limited in width to 2^(INT_BITS-1) (must be positive),
      // we know that any negative shift amount must quality as "huge"
      return _shiftHuge(direction);
    }

    if (shamtInt == 0) {
      return this;
    }

    if (shamtInt >= width) {
      return _shiftHuge(direction);
    }

    switch (direction) {
      case _ShiftType.left:
        return _shiftLeft(shamtInt);
      case _ShiftType.right:
        return _shiftRight(shamtInt);
      case _ShiftType.arithmeticRight:
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

  /// Returns new [LogicValue] replicated [multiplier] times.
  ///
  /// An exception will be thrown in case the multiplier is <1.
  LogicValue replicate(int multiplier) {
    if (multiplier < 1) {
      throw InvalidMultiplierException(multiplier);
    }

    return LogicValue.ofIterable(List.filled(multiplier, this));
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
    return val.toSigned(INT_BITS);
  } else {
    return BigInt.parse(source, radix: 2)
        .toIntUnsigned(source.length)
        .toSigned(INT_BITS);
  }
}

/// Enum for a [LogicValue]'s value.
enum _LogicValueEnum {
  /// A value of 0.
  zero,

  /// A value of 1.
  one,

  /// A value of X (contention).
  x,

  /// A value of Z (floating).
  z;

  /// Indicates whether this is a valid value ([zero] or [one], not [x] or [z]).
  bool get isValid => this == zero || this == one;
}
