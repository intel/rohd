// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_conditional_emitter.dart
// SystemVerilog renderer for backend-neutral conditional emission plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emission_plan.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emitter.dart';

/// Emits SystemVerilog for [Conditional] trees.
class SystemVerilogConditionalEmitter extends ConditionalEmitter {
  /// Input-port names resolved for this conditional block.
  final Map<String, String> inputsNameMap;

  /// Output-port names resolved for this conditional block.
  final Map<String, String> outputsNameMap;

  /// Assignment operator for this conditional block.
  final String assignOperator;

  /// Creates a SystemVerilog conditional emitter.
  const SystemVerilogConditionalEmitter({
    required this.inputsNameMap,
    required this.outputsNameMap,
    required this.assignOperator,
  });

  @override
  String driverFor(Conditional source, Logic driver) =>
      inputsNameMap[source.emissionDriver(driver).name]!;

  @override
  String receiverFor(Conditional source, Logic receiver) =>
      outputsNameMap[source.emissionReceiver(receiver).name]!;

  /// Emits a single assignment statement.
  @override
  String emitAssignment(int indent, String receiverName, String driverName) {
    final padding = Conditional.calcPadding(indent);
    return '$padding$receiverName $assignOperator $driverName;';
  }

  /// Emits an if/else-if/else chain.
  @override
  String emitIf(int indent, List<ConditionalIfBranchEmission> branches) {
    final padding = Conditional.calcPadding(indent);
    final verilog = StringBuffer();
    for (final branch in branches) {
      final header = branch == branches.first
          ? 'if'
          : branch.isElse
              ? 'else'
              : 'else if';
      final condition = branch.isElse ? '' : '(${branch.condition})';
      verilog.write('''
$padding$header$condition begin
${branch.contents}
${padding}end ''');
    }
    verilog.write('\n');

    return verilog.toString();
  }

  /// Emits a case statement.
  @override
  String emitCase(
    ConditionalCaseEmissionPlan plan,
    int indent,
    String expressionName,
    List<ConditionalCaseItemEmission> items,
    String? defaultContents,
  ) {
    var caseHeader = plan.caseBlock.emissionCaseType;
    if (plan.caseBlock.conditionalType == ConditionalType.priority) {
      caseHeader = 'priority $caseHeader';
    } else if (plan.caseBlock.conditionalType == ConditionalType.unique) {
      caseHeader = 'unique $caseHeader';
    }
    final padding = Conditional.calcPadding(indent);
    final verilog = StringBuffer('$padding$caseHeader ($expressionName) \n');
    final subPadding = Conditional.calcPadding(indent + 2);
    for (final item in items) {
      verilog.write('''
$subPadding${item.match} : begin
${item.contents}
${subPadding}end
''');
    }
    if (defaultContents != null) {
      verilog.write('''
${subPadding}default : begin
$defaultContents
${subPadding}end
''');
    }
    verilog.write('${padding}endcase\n');

    return verilog.toString();
  }

  @override
  int ifChildIndent(int indent) => indent + 2;

  @override
  int caseChildIndent(ConditionalCaseEmissionPlan plan, int indent) =>
      indent + 4;
}
