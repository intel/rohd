// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// parameter_const.dart
// Definition of a constant signal that references a module parameter in SV.
//
// 2026 June
// Author: Joel Kimmel

part of 'signals.dart';

/// A [Const]-like signal that emits a [ModuleParameter] name instead of a
/// literal value in generated SystemVerilog.
///
/// In simulation, [ParameterConst] behaves identically to a [Const] — it holds
/// the concrete value of the parameter. In generated SV, wherever this signal
/// would normally appear as a literal (e.g., `8'h8`), it instead appears as
/// the parameter name (e.g., `WIDTH`).
///
/// Example:
/// ```dart
/// final widthParam = ModuleParameter<int>('WIDTH', defaultValue: 8);
/// final widthConst = ParameterConst(widthParam);
/// // In SV: uses 'WIDTH' instead of '8'
/// ```
class ParameterConst extends Const {
  /// The [ModuleParameter] that this constant references.
  final ModuleParameter<int> parameter;

  /// The SystemVerilog expression to emit for this constant.
  ///
  /// Defaults to [ModuleParameter.name], but can be overridden for derived
  /// expressions (e.g., `WIDTH - 1`).
  final String svExpression;

  /// Creates a [ParameterConst] that references [parameter].
  ///
  /// The concrete value is [ModuleParameter.defaultValue], and the width
  /// is determined by [width] (defaulting to the bit-length of the value,
  /// minimum 1).
  ///
  /// An optional [svExpression] can override the SV name (useful for
  /// derived values like `WIDTH - 1`).
  ParameterConst(
    this.parameter, {
    int? width,
    String? svExpression,
  })  : svExpression = svExpression ?? parameter.name,
        super(
          parameter.defaultValue,
          width: width ?? max(parameter.defaultValue.bitLength, 1),
        );

  /// Creates a [ParameterConst] from a [ParameterExpression].
  ///
  /// The concrete value is [ParameterExpression.value], and the SV expression
  /// is [ParameterExpression.svExpression].
  ParameterConst.fromExpression(
    ParameterExpression expr, {
    required this.parameter,
    int? width,
  })  : svExpression = expr.svExpression,
        super(
          expr.value,
          width: width ?? max(expr.value.bitLength, 1),
        );

  @override
  ParameterConst clone({String? name}) =>
      ParameterConst(parameter, width: width, svExpression: svExpression);
}
