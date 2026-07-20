// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_process_emitter.dart
// SystemVerilog renderer for backend-neutral process emission plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/synthesizers/systemverilog/systemverilog_conditional_emitter.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Emits SystemVerilog procedural blocks from [ProcessEmissionPlan]s.
class SystemVerilogProcessEmitter {
  /// Creates a SystemVerilog process emitter.
  const SystemVerilogProcessEmitter();

  /// Emits [plan] using resolved module [ports].
  String emit(
    ProcessEmissionPlan plan,
    String instanceName,
    Map<String, String> ports,
  ) {
    final inputs = Map.fromEntries(
      ports.entries.where((entry) => plan.source.inputs.containsKey(entry.key)),
    );
    final outputs = Map.fromEntries(
      ports.entries
          .where((entry) => plan.source.outputs.containsKey(entry.key)),
    );
    final conditionalEmitter = SystemVerilogConditionalEmitter(
      inputsNameMap: inputs,
      outputsNameMap: outputs,
      assignOperator:
          plan.assignmentKind == ProcessAssignmentKind.blocking ? '=' : '<=',
    );

    final contents = StringBuffer();
    for (final statement in plan.body) {
      contents
        ..write(conditionalEmitter.emitPlan(statement, 1))
        ..write('\n');
    }

    return '''
//  $instanceName
${_header(plan, inputs)} begin
${contents}end
''';
  }

  String _header(ProcessEmissionPlan plan, Map<String, String> inputs) {
    switch (plan.kind) {
      case ProcessEmissionKind.combinational:
        return 'always_comb';
      case ProcessEmissionKind.clocked:
        final triggers = plan.triggers
            .map(
              (trigger) => '${trigger.isPosedge ? 'posedge' : 'negedge'} '
                  '${inputs[trigger.signal.name]}',
            )
            .join(' or ');
        return 'always_ff @($triggers)';
    }
  }
}
