// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional_emitter.dart
// Shared conditional-plan traversal contract for backend renderers.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emission_plan.dart';

/// Shared traversal for rendering [ConditionalEmissionPlan]s in a backend.
abstract class ConditionalEmitter {
  /// Creates a conditional emitter.
  const ConditionalEmitter();

  /// Emits [conditional] at [indent].
  String emit(Conditional conditional, int indent) =>
      emitPlan(ConditionalEmissionPlan.fromConditional(conditional), indent);

  /// Emits [plan] at [indent].
  String emitPlan(ConditionalEmissionPlan plan, int indent) {
    if (plan is ConditionalAssignmentEmissionPlan) {
      final assignment = plan.assignment;
      return emitAssignment(
        indent,
        receiverFor(plan.source, assignment.receiver),
        driverFor(plan.source, assignment.driver),
      );
    }
    if (plan is ConditionalIfEmissionPlan) {
      return emitIf(
        indent,
        [
          for (final branch in plan.branches)
            ConditionalIfBranchEmission(
              isElse: branch.isElse,
              condition: branch.condition == null
                  ? null
                  : driverFor(plan.source, branch.condition!),
              contents: emitChildren(branch.children, ifChildIndent(indent)),
            ),
        ],
      );
    }
    if (plan is ConditionalCaseEmissionPlan) {
      return emitCase(
        plan,
        indent,
        driverFor(plan.source, plan.caseBlock.expression),
        [
          for (final item in plan.items)
            ConditionalCaseItemEmission(
              item: item.source,
              match: driverFor(plan.source, item.source.value),
              contents: emitChildren(
                item.children,
                caseChildIndent(plan, indent),
              ),
            ),
        ],
        plan.defaultChildren == null
            ? null
            : emitChildren(
                plan.defaultChildren!,
                caseChildIndent(plan, indent),
              ),
      );
    }
    if (plan is ConditionalGroupEmissionPlan) {
      return emitGroup(indent, emitChildren(plan.children, indent));
    }

    throw UnsupportedError('Unsupported conditional emission plan: $plan');
  }

  /// Resolves [driver] to a backend expression for [source].
  String driverFor(Conditional source, Logic driver);

  /// Resolves [receiver] to a backend assignment target for [source].
  String receiverFor(Conditional source, Logic receiver);

  /// Emits one assignment.
  String emitAssignment(int indent, String receiver, String driver);

  /// Emits an if tree.
  String emitIf(int indent, List<ConditionalIfBranchEmission> branches);

  /// Emits a case tree.
  String emitCase(
    ConditionalCaseEmissionPlan plan,
    int indent,
    String expression,
    List<ConditionalCaseItemEmission> items,
    String? defaultContents,
  );

  /// Emits a linear conditional group.
  String emitGroup(int indent, String contents) => contents;

  /// Returns the child indentation for an if branch.
  int ifChildIndent(int indent) => indent + 1;

  /// Returns the child indentation for [plan]'s case items.
  int caseChildIndent(ConditionalCaseEmissionPlan plan, int indent) =>
      indent + 1;

  /// Emits [children] with [indent].
  String emitChildren(List<ConditionalEmissionPlan> children, int indent) =>
      children.map((child) => emitPlan(child, indent)).join(childrenSeparator);

  /// Separator used between rendered sibling conditionals.
  String get childrenSeparator => '\n';
}

/// A resolved if branch ready for backend-specific syntax rendering.
class ConditionalIfBranchEmission {
  /// Whether this is an else branch.
  final bool isElse;

  /// Resolved backend condition, or null for an else branch.
  final String? condition;

  /// Rendered child contents.
  final String contents;

  /// Creates a resolved if branch.
  const ConditionalIfBranchEmission({
    required this.isElse,
    required this.condition,
    required this.contents,
  });
}

/// A resolved case item ready for backend-specific syntax rendering.
class ConditionalCaseItemEmission {
  /// Source case item, retained for backend semantic choices.
  final CaseItem item;

  /// Resolved backend case-item expression.
  final String match;

  /// Rendered child contents.
  final String contents;

  /// Creates a resolved case item.
  const ConditionalCaseItemEmission({
    required this.item,
    required this.match,
    required this.contents,
  });
}
