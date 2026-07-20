// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// process_emission_plan_test.dart
// Tests for backend-neutral procedural process emission plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessEmissionPlan', () {
    test('normalizes combinational process semantics', () {
      final source = Logic(name: 'source', width: 4);
      final destination = Logic(name: 'destination', width: 4);
      final process = Combinational([destination < source]);

      final plan = ProcessEmissionPlan.fromAlways(process);

      expect(plan.kind, ProcessEmissionKind.combinational);
      expect(plan.assignmentKind, ProcessAssignmentKind.blocking);
      expect(plan.triggers, isEmpty);
      expect(plan.hasAsyncReset, isFalse);
      expect(plan.body, hasLength(1));
      expect(plan.body.single, isA<ConditionalAssignmentEmissionPlan>());
    });

    test('normalizes sequential edge and assignment semantics', () {
      final risingClock = Logic(name: 'risingClock');
      final fallingClock = Logic(name: 'fallingClock');
      final source = Logic(name: 'source', width: 4);
      final destination = Logic(name: 'destination', width: 4);
      final process = Sequential.multi(
        [risingClock],
        [destination < source],
        negedgeTriggers: [fallingClock],
      );

      final plan = ProcessEmissionPlan.fromAlways(process);

      expect(plan.kind, ProcessEmissionKind.clocked);
      expect(plan.assignmentKind, ProcessAssignmentKind.nonBlocking);
      expect(plan.hasAsyncReset, isFalse);
      expect(
        plan.triggers.map((trigger) => trigger.isPosedge),
        [true, false],
      );
      expect(plan.body, hasLength(1));
      expect(plan.body.single, isA<ConditionalAssignmentEmissionPlan>());
    });
  });
}
