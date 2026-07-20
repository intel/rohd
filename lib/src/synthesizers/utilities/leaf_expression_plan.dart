// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_expression_plan.dart
// Normalized semantic plans for inline leaf expression rendering.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/leaf_cell_spec.dart';
import 'package:rohd/src/synthesizers/utilities/leaf_cell_spec_inference.dart';

/// Normalized planning data for rendering an inline leaf expression.
class LeafExpressionPlan {
  /// Module whose leaf semantics are being rendered.
  final Module sourceModule;

  /// Semantic operation kind when available.
  final LeafOperationKind? operation;

  /// Semantic metadata when available.
  final Map<String, Object?> metadata;

  /// Ordered input expressions.
  final List<String> inputValues;

  /// Input expressions keyed by port name.
  final Map<String, String> inputsByPort;

  /// Creates a new [LeafExpressionPlan].
  const LeafExpressionPlan({
    required this.sourceModule,
    required this.operation,
    required this.metadata,
    required this.inputValues,
    required this.inputsByPort,
  });

  /// Builds a plan for [module] and [inputs].
  factory LeafExpressionPlan.fromInlineModule(
    InlineSystemVerilog module,
    Map<String, String> inputs,
  ) {
    final spec = leafCellSpecForInlineModule(module);
    return LeafExpressionPlan(
      sourceModule: module,
      operation: spec?.operation,
      metadata: spec?.metadata ?? const {},
      inputValues: inputs.values.toList(),
      inputsByPort: Map.unmodifiable(inputs),
    );
  }

  /// Returns metadata [key] cast as [T], or `null` if absent/mismatched.
  T? meta<T>(String key) {
    final value = metadata[key];
    return value is T ? value : null;
  }

  /// Invokes the legacy SystemVerilog inline hook for this source module.
  ///
  /// This exists only for the staged SystemVerilog migration. Other backends
  /// must emit [operation] or use an explicit backend extension.
  String legacySystemVerilogExpression() =>
      (sourceModule as InlineSystemVerilog).inlineVerilog(inputsByPort);
}
