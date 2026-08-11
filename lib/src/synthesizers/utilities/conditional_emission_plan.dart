// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional_emission_plan.dart
// Backend-neutral semantic plans for conditional emission trees.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Backend-neutral description of a [Conditional] emission tree.
abstract class ConditionalEmissionPlan {
  /// The source conditional represented by this plan.
  final Conditional source;

  /// Creates an emission plan for [source].
  const ConditionalEmissionPlan(this.source);

  /// Creates a plan for [conditional] and all of its children.
  factory ConditionalEmissionPlan.fromConditional(Conditional conditional) {
    if (conditional is ConditionalAssign) {
      return ConditionalAssignmentEmissionPlan(conditional);
    }
    if (conditional is If) {
      return ConditionalIfEmissionPlan(
        conditional,
        [
          for (final branch in conditional.iffs)
            ConditionalIfBranchEmissionPlan(
              branch,
              branch is Else ? null : branch.condition,
              [
                for (final child in branch.then)
                  ConditionalEmissionPlan.fromConditional(child),
              ],
            ),
        ],
      );
    }
    if (conditional is Case) {
      return ConditionalCaseEmissionPlan(
        conditional,
        [
          for (final item in conditional.items)
            ConditionalCaseItemEmissionPlan(
              item,
              [
                for (final child in item.then)
                  ConditionalEmissionPlan.fromConditional(child),
              ],
            ),
        ],
        conditional.defaultItem == null
            ? null
            : [
                for (final child in conditional.defaultItem!)
                  ConditionalEmissionPlan.fromConditional(child),
              ],
      );
    }
    if (conditional is ConditionalGroup) {
      return ConditionalGroupEmissionPlan(
        conditional,
        [
          for (final child in conditional.conditionals)
            ConditionalEmissionPlan.fromConditional(child),
        ],
      );
    }

    throw UnsupportedError(
      'Unsupported Conditional type for emission: ${conditional.runtimeType}',
    );
  }
}

/// Plan for a [ConditionalAssign].
class ConditionalAssignmentEmissionPlan extends ConditionalEmissionPlan {
  /// The assignment represented by this plan.
  ConditionalAssign get assignment => source as ConditionalAssign;

  /// Creates an assignment plan.
  const ConditionalAssignmentEmissionPlan(super.source);
}

/// Plan for an [If] tree.
class ConditionalIfEmissionPlan extends ConditionalEmissionPlan {
  /// The ordered branches of this if tree.
  final List<ConditionalIfBranchEmissionPlan> branches;

  /// Creates an if plan.
  const ConditionalIfEmissionPlan(super.source, this.branches);
}

/// Plan for one branch of an [If].
class ConditionalIfBranchEmissionPlan {
  /// The original branch.
  final Iff source;

  /// The branch condition, or null for an else branch.
  final Logic? condition;

  /// Plans emitted when this branch is selected.
  final List<ConditionalEmissionPlan> children;

  /// Creates an if branch plan.
  const ConditionalIfBranchEmissionPlan(
    this.source,
    this.condition,
    this.children,
  );

  /// Whether this is the final else branch.
  bool get isElse => source is Else;
}

/// Plan for a [Case] tree.
class ConditionalCaseEmissionPlan extends ConditionalEmissionPlan {
  /// The ordered case items.
  final List<ConditionalCaseItemEmissionPlan> items;

  /// Plans emitted when no case item matches.
  final List<ConditionalEmissionPlan>? defaultChildren;

  /// The case represented by this plan.
  Case get caseBlock => source as Case;

  /// Creates a case plan.
  const ConditionalCaseEmissionPlan(
    super.source,
    this.items,
    this.defaultChildren,
  );
}

/// Plan for one [CaseItem].
class ConditionalCaseItemEmissionPlan {
  /// The original case item.
  final CaseItem source;

  /// Plans emitted when [source] matches.
  final List<ConditionalEmissionPlan> children;

  /// Creates a case item plan.
  const ConditionalCaseItemEmissionPlan(this.source, this.children);
}

/// Plan for a [ConditionalGroup].
class ConditionalGroupEmissionPlan extends ConditionalEmissionPlan {
  /// Plans emitted in source order.
  final List<ConditionalEmissionPlan> children;

  /// Creates a group plan.
  const ConditionalGroupEmissionPlan(super.source, this.children);
}
