// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_parameter.dart
// Definition of configurable module parameters for SV generation.
//
// 2026 June
// Author: Joel Kimmel

import 'package:rohd/rohd.dart';

/// Represents a configurable parameter on a [Module] that maps to a
/// SystemVerilog `parameter` or `localparam` declaration.
///
/// In simulation, [ModuleParameter] wraps a concrete Dart value of type [T]
/// and behaves identically to that value. In generated SystemVerilog, it
/// appears as a named parameter in the module definition.
///
/// Example:
/// ```dart
/// final width = ModuleParameter<int>('WIDTH', defaultValue: 8);
/// final depth = ModuleParameter<int>('DEPTH',
///     defaultValue: 256, isLocalParam: true);
/// ```
class ModuleParameter<T> {
  /// The SystemVerilog name for this parameter (e.g., `'WIDTH'`).
  final String name;

  /// The concrete value of this parameter used during simulation.
  final T defaultValue;

  /// The SystemVerilog type string for this parameter (e.g., `'int'`).
  ///
  /// If not provided, it is inferred from [T]:
  /// - `int` → `'int'`
  /// - `bool` → `'bit'`
  /// - Otherwise, must be provided explicitly.
  final String svType;

  /// Whether this parameter is a `localparam` (cannot be overridden at
  /// instantiation) rather than a `parameter`.
  final bool isLocalParam;

  /// A SystemVerilog expression for the default value.
  ///
  /// If not provided, it is generated from [defaultValue] using
  /// [_defaultSvValue].
  final String? svDefaultValue;

  /// Creates a [ModuleParameter] with the given [name] and [defaultValue].
  ///
  /// The [svType] is inferred from [T] if not provided. Set [isLocalParam]
  /// to `true` for a `localparam` declaration.
  ModuleParameter(
    this.name, {
    required this.defaultValue,
    String? svType,
    this.isLocalParam = false,
    this.svDefaultValue,
  }) : svType = svType ?? _inferSvType<T>();

  /// Infers a SystemVerilog type string from the Dart type [U].
  static String _inferSvType<U>() {
    if (U == int) {
      return 'int';
    }
    if (U == bool) {
      return 'bit';
    }
    throw ArgumentError('Cannot infer SV type for Dart type $U. '
        'Provide an explicit svType.');
  }

  /// Returns the SV default value string for this parameter.
  String get svDefault => svDefaultValue ?? _defaultSvValue();

  /// Generates a default SV value string from [defaultValue].
  String _defaultSvValue() {
    final v = defaultValue;
    if (v is int) {
      return '$v';
    }
    if (v is bool) {
      return v ? "1'b1" : "1'b0";
    }
    return '$v';
  }

  /// Converts this parameter to a [SystemVerilogParameterDefinition] suitable
  /// for inclusion in a module definition header.
  SystemVerilogParameterDefinition toSvParameterDefinition() =>
      SystemVerilogParameterDefinition(
        name,
        type: svType,
        defaultValue: svDefault,
        isLocalParam: isLocalParam,
      );

  /// Creates a [ParameterExpression] from this parameter.
  ///
  /// Only valid for `int` parameters.
  ParameterExpression toExpression() {
    if (defaultValue is! int) {
      throw StateError('toExpression() is only supported for int parameters, '
          'but $name has type $T.');
    }
    return ParameterExpression.ofParam(this as ModuleParameter<int>);
  }

  @override
  String toString() => 'ModuleParameter($name=$defaultValue)';
}

/// Represents a value that has both a concrete Dart [int] value (for
/// simulation) and a SystemVerilog expression string (for code generation).
///
/// This is used wherever widths or integer values flow into SV generation
/// and need to remain symbolic (e.g., `WIDTH - 1` instead of `7`).
///
/// Example:
/// ```dart
/// final widthParam = ModuleParameter<int>('WIDTH', defaultValue: 8);
/// final widthExpr = ParameterExpression.ofParam(widthParam);
/// final rangeExpr = widthExpr - 1; // value=7, svExpression='WIDTH - 1'
/// ```
class ParameterExpression {
  /// The concrete Dart value, used during simulation.
  final int value;

  /// The SystemVerilog expression string, used during code generation.
  final String svExpression;

  /// Creates a [ParameterExpression] with explicit [value] and
  /// [svExpression].
  const ParameterExpression(this.value, this.svExpression);

  /// Creates a [ParameterExpression] from a [ModuleParameter].
  ///
  /// The [svExpression] is set to the parameter's [ModuleParameter.name].
  ParameterExpression.ofParam(ModuleParameter<int> param)
      : value = param.defaultValue,
        svExpression = param.name;

  /// Creates a [ParameterExpression] from a plain integer constant.
  ///
  /// The [svExpression] is the decimal string representation of [value].
  ParameterExpression.ofInt(this.value) : svExpression = '$value';

  /// Addition.
  ParameterExpression operator +(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value + other.value, '$svExpression + ${other.svExpression}');
    }
    if (other is int) {
      return ParameterExpression(value + other, '$svExpression + $other');
    }
    throw ArgumentError('Cannot add $runtimeType and ${other.runtimeType}');
  }

  /// Subtraction.
  ParameterExpression operator -(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value - other.value, '$svExpression - ${other.svExpression}');
    }
    if (other is int) {
      return ParameterExpression(value - other, '$svExpression - $other');
    }
    throw ArgumentError(
        'Cannot subtract $runtimeType and ${other.runtimeType}');
  }

  /// Multiplication.
  ParameterExpression operator *(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value * other.value, '($svExpression) * (${other.svExpression})');
    }
    if (other is int) {
      return ParameterExpression(value * other, '($svExpression) * $other');
    }
    throw ArgumentError(
        'Cannot multiply $runtimeType and ${other.runtimeType}');
  }

  /// Integer division.
  ParameterExpression operator ~/(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value ~/ other.value, '($svExpression) / (${other.svExpression})');
    }
    if (other is int) {
      return ParameterExpression(value ~/ other, '($svExpression) / $other');
    }
    throw ArgumentError('Cannot divide $runtimeType and ${other.runtimeType}');
  }

  /// Left shift.
  ParameterExpression operator <<(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value << other.value, '($svExpression) << (${other.svExpression})');
    }
    if (other is int) {
      return ParameterExpression(value << other, '($svExpression) << $other');
    }
    throw ArgumentError(
        'Cannot left-shift $runtimeType by ${other.runtimeType}');
  }

  /// Right shift.
  ParameterExpression operator >>(Object other) {
    if (other is ParameterExpression) {
      return ParameterExpression(
          value >> other.value, '($svExpression) >> (${other.svExpression})');
    }
    if (other is int) {
      return ParameterExpression(value >> other, '($svExpression) >> $other');
    }
    throw ArgumentError(
        'Cannot right-shift $runtimeType by ${other.runtimeType}');
  }

  @override
  String toString() => 'ParameterExpression($value, "$svExpression")';
}
