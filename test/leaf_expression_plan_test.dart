// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_expression_plan_test.dart
// Tests for normalized semantic leaf expression plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

import 'leaf_test_module_factories.dart';

void main() {
  group('LeafExpressionPlan', () {
    test('captures operation, metadata and ordered inputs', () {
      final control = Logic(name: 'control');
      final d1 = Logic(name: 'd1', width: 4);
      final d0 = Logic(name: 'd0', width: 4);
      final mux = Mux(control, d1, d0);

      final plan = LeafExpressionPlan.fromInlineModule(mux, {
        mux.inputs.keys.elementAt(0): 'ctrl_expr',
        mux.inputs.keys.elementAt(1): 'd0_expr',
        mux.inputs.keys.elementAt(2): 'd1_expr',
      });

      expect(plan.operation, LeafOperationKind.mux);
      expect(plan.meta<int>('outputWidth'), 4);
      expect(plan.inputValues, ['ctrl_expr', 'd0_expr', 'd1_expr']);
    });

    test('returns null metadata for missing keys or wrong types', () {
      final gate = And2Gate(Logic(name: 'a'), Logic(name: 'b'));
      final plan =
          LeafExpressionPlan.fromInlineModule(gate, {'in0': 'a', 'in1': 'b'});

      expect(plan.meta<int>('missingKey'), isNull);
      expect(plan.meta<String>('missingKey'), isNull);
    });

    test('planner contract matrix across representative leaf operations', () {
      Map<String, String> orderedInputs(
        InlineLeaf module,
        List<String> values,
      ) {
        final keys = module.inputs.keys.toList();
        expect(values.length, keys.length);
        return Map.fromIterables(keys, values);
      }

      final mux = Mux(
        Logic(name: 'sel'),
        Logic(name: 'd1', width: 4),
        Logic(name: 'd0', width: 4),
      );
      final busSubset = BusSubset(Logic(name: 'bus', width: 12), 9, 4);
      final shift = LShift(
        Logic(name: 'lhs', width: 9),
        Logic(name: 'sh', width: 4),
      );
      final replication = ReplicationOp(Logic(name: 'rep_in', width: 3), 4);
      final swizzle = Swizzle([
        Logic(name: 'a', width: 2),
        Logic(name: 'b'),
        Logic(name: 'c', width: 3),
      ]);

      final scenarios = <({
        InlineLeaf module,
        LeafOperationKind op,
        List<String> inputs,
        Map<String, Object?> metadata,
      })>[
        (
          module: mux,
          op: LeafOperationKind.mux,
          inputs: ['sel_expr', 'd0_expr', 'd1_expr'],
          metadata: {'outputWidth': 4},
        ),
        (
          module: busSubset,
          op: LeafOperationKind.busSubset,
          inputs: ['bus_expr'],
          metadata: {
            'inputWidth': 12,
            'startIndex': 9,
            'endIndex': 4,
          },
        ),
        (
          module: shift,
          op: LeafOperationKind.shiftLeft,
          inputs: ['lhs_expr', 'sh_expr'],
          metadata: {
            'inputWidth': 9,
            'shiftAmountWidth': 4,
          },
        ),
        (
          module: replication,
          op: LeafOperationKind.replication,
          inputs: ['rep_expr'],
          metadata: {
            'inputWidth': 3,
            'outputWidth': 12,
            'replicationCount': 4,
          },
        ),
        (
          module: swizzle,
          op: LeafOperationKind.swizzle,
          inputs: ['a_expr', 'b_expr', 'c_expr'],
          metadata: {
            'inputCount': 3,
            'inputWidths': [3, 1, 2],
            'inputIsArrayMember': [false, false, false],
            'inputHasUnpackedArraySource': [false, false, false],
          },
        ),
      ];

      for (final scenario in scenarios) {
        final plan = LeafExpressionPlan.fromInlineModule(
          scenario.module,
          orderedInputs(scenario.module, scenario.inputs),
        );

        expect(plan.operation, scenario.op);
        expect(plan.inputValues, scenario.inputs);
        expect(plan.inputsByPort.values.toList(), scenario.inputs);

        for (final entry in scenario.metadata.entries) {
          expect(plan.metadata[entry.key], entry.value);
        }
      }
    });

    test('plan mirrors inferred leaf spec across module matrix', () {
      Map<String, String> taggedInputs(InlineLeaf module) {
        final mapping = <String, String>{};
        for (final port in module.inputs.keys) {
          mapping[port] = '${port}_expr';
        }
        return mapping;
      }

      final modules = representativeInlineLeafModules();

      for (final module in modules) {
        final inferred = leafCellSpecForInlineModule(module);
        expect(inferred, isNotNull,
            reason: 'Expected inference for ${module.runtimeType}.');

        final inputs = taggedInputs(module);
        final plan = LeafExpressionPlan.fromInlineModule(module, inputs);

        expect(
          plan.operation,
          inferred!.operation,
          reason: 'Operation mismatch for ${module.runtimeType}.',
        );
        expect(
          plan.metadata,
          inferred.metadata,
          reason: 'Metadata mismatch for ${module.runtimeType}.',
        );
        expect(
          plan.inputsByPort,
          inputs,
          reason: 'Input map mismatch for ${module.runtimeType}.',
        );
        expect(
          plan.inputValues,
          inputs.values.toList(),
          reason: 'Input ordering mismatch for ${module.runtimeType}.',
        );
      }
    });
  });
}
