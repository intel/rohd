// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// process_emission_plan.dart
// Backend-neutral semantic plans for procedural process emission.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/always.dart';
import 'package:rohd/src/synthesizers/utilities/conditional_emission_plan.dart';

/// The semantic class of a procedural process.
enum ProcessEmissionKind {
  /// A process reevaluated when its inputs change.
  combinational,

  /// A process reevaluated on one or more clock edges.
  clocked,
}

/// The assignment semantics used inside a procedural process.
enum ProcessAssignmentKind {
  /// Assign immediately within the process.
  blocking,

  /// Assign at the end of the current time step.
  nonBlocking,
}

/// A clock-edge trigger in a [ProcessEmissionPlan].
class ProcessTriggerEmissionPlan {
  /// The trigger signal.
  final Logic signal;

  /// Whether this trigger is a rising edge.
  final bool isPosedge;

  /// Creates a clock-edge trigger plan.
  const ProcessTriggerEmissionPlan(this.signal, {required this.isPosedge});
}

/// Backend-neutral description of an [Always] procedural block.
class ProcessEmissionPlan {
  /// The source process.
  final Always source;

  /// Whether this is combinational or clocked logic.
  final ProcessEmissionKind kind;

  /// Assignment semantics for statements in [body].
  final ProcessAssignmentKind assignmentKind;

  /// Clock-edge triggers for a clocked process.
  final List<ProcessTriggerEmissionPlan> triggers;

  /// Whether a clocked process has an asynchronous reset trigger.
  final bool hasAsyncReset;

  /// Backend-neutral statement plans in source order.
  final List<ConditionalEmissionPlan> body;

  /// Creates a procedural process plan.
  const ProcessEmissionPlan({
    required this.source,
    required this.kind,
    required this.assignmentKind,
    required this.triggers,
    required this.hasAsyncReset,
    required this.body,
  });

  /// Builds a normalized plan for [always].
  factory ProcessEmissionPlan.fromAlways(Always always) {
    if (always is Combinational) {
      return ProcessEmissionPlan(
        source: always,
        kind: ProcessEmissionKind.combinational,
        assignmentKind: ProcessAssignmentKind.blocking,
        triggers: const [],
        hasAsyncReset: false,
        body: [
          for (final conditional in always.conditionals)
            ConditionalEmissionPlan.fromConditional(conditional),
        ],
      );
    }
    if (always is Sequential) {
      return ProcessEmissionPlan(
        source: always,
        kind: ProcessEmissionKind.clocked,
        assignmentKind: ProcessAssignmentKind.nonBlocking,
        triggers: [
          for (final trigger in always.emissionTriggers)
            ProcessTriggerEmissionPlan(
              trigger.signal,
              isPosedge: trigger.isPosedge,
            ),
        ],
        hasAsyncReset: always.asyncReset,
        body: [
          for (final conditional in always.conditionals)
            ConditionalEmissionPlan.fromConditional(conditional),
        ],
      );
    }

    throw UnsupportedError(
      'Unsupported procedural process for emission: ${always.runtimeType}',
    );
  }
}
