// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_conditional_emitter.dart
// SystemC renderer for backend-neutral conditional emission plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emission_plan.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emitter.dart';

/// Emits SystemC/C++ syntax for backend-neutral conditional emission plans.
class SystemCConditionalEmitter extends ConditionalEmitter {
  /// Resolves a conditional driver to a SystemC expression.
  final String Function(Logic driver) driverExpressionFor;

  /// Resolves a conditional receiver to a SystemC assignment target.
  final String Function(Logic receiver) receiverExpressionFor;

  /// Whether a case-item value can be emitted as a C++ switch label.
  final bool Function(Logic value) isConstCaseItem;

  /// Emits a comparison condition for a case item lowered to an if chain.
  final String Function(
    Logic value,
    String expression, {
    required bool isCaseZ,
  }) caseItemConditionFor;

  /// Creates a SystemC conditional emitter.
  const SystemCConditionalEmitter({
    required this.driverExpressionFor,
    required this.receiverExpressionFor,
    required this.isConstCaseItem,
    required this.caseItemConditionFor,
  });

  @override
  String driverFor(Conditional source, Logic driver) =>
      driverExpressionFor(driver);

  @override
  String receiverFor(Conditional source, Logic receiver) =>
      receiverExpressionFor(receiver);

  @override
  String emitAssignment(int indent, String receiver, String driver) =>
      '${Conditional.calcPadding(indent)}$receiver = $driver;\n';

  @override
  String emitIf(int indent, List<ConditionalIfBranchEmission> branches) {
    final padding = Conditional.calcPadding(indent);
    final buffer = StringBuffer();
    for (final branch in branches) {
      final header = branch == branches.first
          ? 'if'
          : branch.isElse
              ? ' else'
              : ' else if';
      final condition = branch.isElse ? '' : ' (${branch.condition})';
      buffer
        ..write('$padding$header$condition {\n')
        ..write(branch.contents)
        ..write('$padding}');
    }
    buffer.writeln();
    return buffer.toString();
  }

  @override
  String emitCase(
    ConditionalCaseEmissionPlan plan,
    int indent,
    String expression,
    List<ConditionalCaseItemEmission> items,
    String? defaultContents,
  ) {
    if (!_usesSwitch(plan)) {
      return _emitCaseAsIfElse(
        plan,
        indent,
        expression,
        items,
        defaultContents,
      );
    }

    final padding = Conditional.calcPadding(indent);
    final buffer = StringBuffer()..writeln('${padding}switch ($expression) {');
    for (final item in items) {
      buffer
        ..writeln('$padding  case ${item.match}:')
        ..write(item.contents)
        ..writeln('$padding    break;');
    }
    if (defaultContents != null) {
      buffer
        ..writeln('$padding  default:')
        ..write(defaultContents)
        ..writeln('$padding    break;');
    }
    buffer.writeln('$padding}');
    return buffer.toString();
  }

  @override
  int caseChildIndent(ConditionalCaseEmissionPlan plan, int indent) =>
      _usesSwitch(plan) ? indent + 2 : indent + 1;

  @override
  String get childrenSeparator => '';

  bool _usesSwitch(ConditionalCaseEmissionPlan plan) =>
      plan.caseBlock is! CaseZ &&
      plan.items.every((item) => isConstCaseItem(item.source.value));

  String _emitCaseAsIfElse(
    ConditionalCaseEmissionPlan plan,
    int indent,
    String expression,
    List<ConditionalCaseItemEmission> items,
    String? defaultContents,
  ) {
    final padding = Conditional.calcPadding(indent);
    final buffer = StringBuffer();
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final condition = caseItemConditionFor(
        item.item.value,
        expression,
        isCaseZ: plan.caseBlock is CaseZ,
      );
      final header = index == 0 ? 'if' : ' else if';
      buffer
        ..write('$padding$header ($condition) {\n')
        ..write(item.contents)
        ..write('$padding}');
    }
    if (defaultContents != null) {
      buffer
        ..write(' else {\n')
        ..write(defaultContents)
        ..write('$padding}');
    }
    buffer.writeln();
    return buffer.toString();
  }
}
