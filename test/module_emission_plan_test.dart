// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_emission_plan_test.dart
// Tests for backend-neutral resolved module emission plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

class _ModuleEmissionPlanChild extends Module {
  _ModuleEmissionPlanChild(Logic input) {
    input = addInput('inputValue', input, width: input.width);
    final output = addOutput('outputValue', width: input.width);
    output <= input;
  }
}

class _ModuleEmissionPlanFixture extends Module {
  _ModuleEmissionPlanFixture(Logic input) {
    input = addInput('inputValue', input, width: input.width);
    final output = addOutput('outputValue', width: input.width);
    output <= _ModuleEmissionPlanChild(input).output('outputValue');
  }
}

void main() {
  test('captures resolved ports and instances', () async {
    final module = _ModuleEmissionPlanFixture(Logic(name: 'input', width: 4));
    await module.build();

    final plan =
        ModuleEmissionPlan.fromDefinition(SynthModuleDefinition(module));

    expect(plan.sourceModule, same(module));
    expect(plan.inputs.map((signal) => signal.name), ['inputValue']);
    expect(plan.outputs.map((signal) => signal.name), ['outputValue']);
    expect(plan.inOuts, isEmpty);
    expect(plan.instances, hasLength(1));
    expect(plan.instances.single.module, isA<_ModuleEmissionPlanChild>());
  });
}
