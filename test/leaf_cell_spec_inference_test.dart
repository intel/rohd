// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_cell_spec_inference_test.dart
// Tests for semantic leaf-cell metadata inference.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

import 'leaf_test_module_factories.dart';

void main() {
  group('leafCellSpecForInlineModule', () {
    test('infers operation kind for simple gate', () {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final gate = And2Gate(a, b);

      final spec = leafCellSpecForInlineModule(gate);

      expect(spec, isNotNull);
      expect(spec!.operation, LeafOperationKind.and);
    });

    test('includes bus subset metadata', () {
      final bus = Logic(name: 'bus', width: 12);
      final subset = BusSubset(bus, 9, 4);

      final spec = leafCellSpecForInlineModule(subset);

      expect(spec, isNotNull);
      expect(spec!.operation, LeafOperationKind.busSubset);
      expect(spec.metadata['inputWidth'], 12);
      expect(spec.metadata['startIndex'], 9);
      expect(spec.metadata['endIndex'], 4);
    });

    test('includes mux and replication width metadata', () {
      final control = Logic(name: 'control');
      final d0 = Logic(name: 'd0', width: 5);
      final d1 = Logic(name: 'd1', width: 5);
      final mux = Mux(control, d1, d0);
      final replication = ReplicationOp(Logic(name: 'in', width: 3), 4);

      final muxSpec = leafCellSpecForInlineModule(mux);
      final replicationSpec = leafCellSpecForInlineModule(replication);

      expect(muxSpec, isNotNull);
      expect(muxSpec!.operation, LeafOperationKind.mux);
      expect(muxSpec.metadata['outputWidth'], 5);

      expect(replicationSpec, isNotNull);
      expect(replicationSpec!.operation, LeafOperationKind.replication);
      expect(replicationSpec.metadata['inputWidth'], 3);
      expect(replicationSpec.metadata['outputWidth'], 12);
      expect(replicationSpec.metadata['replicationCount'], 4);
    });

    test('includes width metadata for unary, shift, and swizzle', () {
      final unary = AndUnary(Logic(name: 'u', width: 6));
      final shift =
          LShift(Logic(name: 's', width: 9), Logic(name: 'sh', width: 4));
      final swizzle = Swizzle([
        Logic(name: 'a', width: 2),
        Logic(name: 'b'),
        Logic(name: 'c', width: 3),
      ]);

      final unarySpec = leafCellSpecForInlineModule(unary);
      final shiftSpec = leafCellSpecForInlineModule(shift);
      final swizzleSpec = leafCellSpecForInlineModule(swizzle);

      expect(unarySpec, isNotNull);
      expect(unarySpec!.metadata['inputWidth'], 6);

      expect(shiftSpec, isNotNull);
      expect(shiftSpec!.metadata['inputWidth'], 9);
      expect(shiftSpec.metadata['shiftAmountWidth'], 4);

      expect(swizzleSpec, isNotNull);
      expect(swizzleSpec!.metadata['inputCount'], 3);
      expect(
        swizzleSpec.metadata['inputWidths'],
        swizzle.inputs.values.map((input) => input.width).toList(),
      );
      expect(
        swizzleSpec.metadata['inputIsArrayMember'],
        swizzle.inputs.values.map((input) => input.isArrayMember).toList(),
      );
      expect(
        swizzleSpec.metadata['inputHasUnpackedArraySource'],
        [false, false, false],
      );
    });

    test('inference contract matrix across representative leaf operations', () {
      final swizzle = Swizzle([
        Logic(name: 'a', width: 2),
        Logic(name: 'b'),
        Logic(name: 'c', width: 3),
      ]);

      final scenarios = <({
        InlineLeaf module,
        LeafOperationKind operation,
        Map<String, Object?> metadata,
      })>[
        (
          module: NotGate(Logic(name: 'n', width: 7)),
          operation: LeafOperationKind.not,
          metadata: {'outputWidth': 7},
        ),
        (
          module: Mux(
            Logic(name: 'sel'),
            Logic(name: 'd1', width: 4),
            Logic(name: 'd0', width: 4),
          ),
          operation: LeafOperationKind.mux,
          metadata: {'outputWidth': 4},
        ),
        (
          module: LShift(
            Logic(name: 'lhs', width: 9),
            Logic(name: 'sh', width: 4),
          ),
          operation: LeafOperationKind.shiftLeft,
          metadata: {
            'inputWidth': 9,
            'shiftAmountWidth': 4,
          },
        ),
        (
          module: BusSubset(Logic(name: 'bus', width: 12), 9, 4),
          operation: LeafOperationKind.busSubset,
          metadata: {
            'inputWidth': 12,
            'startIndex': 9,
            'endIndex': 4,
          },
        ),
        (
          module: ReplicationOp(Logic(name: 'in', width: 3), 4),
          operation: LeafOperationKind.replication,
          metadata: {
            'inputWidth': 3,
            'outputWidth': 12,
            'replicationCount': 4,
          },
        ),
        (
          module: Power(
            Logic(name: 'base', width: 5),
            Logic(name: 'exp', width: 5),
          ),
          operation: LeafOperationKind.power,
          metadata: {
            'inputWidth': 5,
            'makeSelfDetermined': true,
          },
        ),
        (
          module: IndexGate(
            Logic(name: 'word', width: 8),
            Logic(name: 'idx', width: 3),
          ),
          operation: LeafOperationKind.bitIndex,
          metadata: {'originalWidth': 8},
        ),
        (
          module: swizzle,
          operation: LeafOperationKind.swizzle,
          metadata: {
            'inputCount': 3,
            'inputWidths':
                swizzle.inputs.values.map((input) => input.width).toList(),
            'inputIsArrayMember': swizzle.inputs.values
                .map((input) => input.isArrayMember)
                .toList(),
            'inputHasUnpackedArraySource': [false, false, false],
          },
        ),
      ];

      for (final scenario in scenarios) {
        final spec = leafCellSpecForInlineModule(scenario.module);

        expect(spec, isNotNull);
        expect(spec!.operation, scenario.operation);

        for (final entry in scenario.metadata.entries) {
          expect(spec.metadata[entry.key], entry.value);
        }
      }
    });

    test('all known built-in inline leaf modules are inferable', () {
      final modules = allKnownInlineLeafModules();

      for (final module in modules) {
        final spec = leafCellSpecForInlineModule(module);
        expect(
          spec,
          isNotNull,
          reason: 'Missing inference mapping for built-in inline module '
              '${module.runtimeType}.',
        );
      }
    });
  });
}
