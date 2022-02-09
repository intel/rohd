/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_value.dart
/// Definition for a single bit of logical value
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

/***/

/// Represents a single logical 4-value bit (`0`, `1`, `x`, or `z`).
class LogicValue {
  /// Logical value of `0`
  static const LogicValue zero = LogicValue._(_LogicValueEnum.zero);

  /// Logical value of `1`
  static const LogicValue one = LogicValue._(_LogicValueEnum.one);

  /// Logical value of `x`
  static const LogicValue x = LogicValue._(_LogicValueEnum.x);

  /// Logical value of `z`
  static const LogicValue z = LogicValue._(_LogicValueEnum.z);

  /// Convert a bool to a one or zero
  static LogicValue ofBool(bool value) => value ? one : zero;

  /// Convert a bool to a one or zero
  @Deprecated('Use `ofBool` instead.')
  static LogicValue fromBool(bool value) => ofBool(value);

  final _LogicValueEnum _value;
  const LogicValue._(this._value);

  /// Returns true iff [other] has the same logical value as [this].
  @override
  bool operator ==(Object other) =>
      other is LogicValue && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() {
    return this == LogicValue.x
        ? 'x'
        : this == LogicValue.z
            ? 'z'
            : this == LogicValue.one
                ? '1'
                : '0';
  }

  /// Logical inversion.  Returns `x` if invalid.
  LogicValue operator ~() {
    if (!isValid) return LogicValue.x;
    return this == LogicValue.zero ? LogicValue.one : LogicValue.zero;
  }

  /// Logical AND operation.
  LogicValue operator &(LogicValue other) {
    if (this == LogicValue.zero || other == LogicValue.zero) {
      return LogicValue.zero;
    }
    if (!isValid || !other.isValid) return LogicValue.x;
    return (this == LogicValue.one && other == LogicValue.one)
        ? LogicValue.one
        : LogicValue.zero;
  }

  /// Logical OR operation.
  LogicValue operator |(LogicValue other) {
    return (this == LogicValue.one || other == LogicValue.one)
        ? LogicValue.one
        : (isValid && other.isValid)
            ? LogicValue.zero
            : LogicValue.x;
  }

  /// Logical XOR operation.
  LogicValue operator ^(LogicValue other) {
    if (!isValid || !other.isValid) return LogicValue.x;
    return ((this == LogicValue.one) ^ (other == LogicValue.one))
        ? LogicValue.one
        : LogicValue.zero;
  }

  /// Returns true iff the value is `0` or `1`.
  bool get isValid => !(this == LogicValue.x || this == LogicValue.z);

  //TODO: consider pessimism/optimism impact here for both design and validation

  /// Returns true iff the transition represents a positive edge.
  ///
  /// Only returns true from 0 -> 1.  If [previousValue] or [newValue] is invalid, an Exception will be
  /// thrown, unless [ignoreInvalid] is set to `true`.
  static bool isPosedge(LogicValue previousValue, LogicValue newValue,
      {ignoreInvalid = false}) {
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
    if (!ignoreInvalid && (!previousValue.isValid | !newValue.isValid)) {
      throw Exception(
          'Edge detection on invalid value from $previousValue to $newValue');
    }
    return previousValue == LogicValue.one && newValue == LogicValue.zero;
  }

  /// Converts a valid logical value to a boolean.
  ///
  /// Throws an exception if the value is invalid.
  bool toBool() {
    if (!isValid) throw Exception('Cannot convert value "$this" to bool');
    return this == LogicValue.one ? true : false;
  }

  /// Converts a valid logical value to an [int].
  ///
  /// Throws an exception if the value is invalid.
  int toInt() {
    return toBool() ? 1 : 0;
  }
}

/// Converts a binary [String] representation to a binary [int].
///
/// Exactly equivalent to `int.parse(s, radix:2)`, but shorter to type.
int bin(String s) => int.parse(s, radix: 2);

/// Enum for a [LogicValue]'s value.
enum _LogicValueEnum { zero, one, x, z }
