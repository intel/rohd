// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_tree_model_test.dart
// Tests for signal and module-tree data models.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

void main() {
  group('SignalModel', () {
    test('round trips through a map', () {
      final signal = SignalModel(
        name: 'accumulator',
        direction: 'Output',
        value: "8'h2a",
        width: 8,
      );

      final restored = SignalModel.fromMap(signal.toMap());

      expect(restored.name, signal.name);
      expect(restored.direction, signal.direction);
      expect(restored.value, signal.value);
      expect(restored.width, signal.width);
    });
  });

  group('TreeModel.fromJson', () {
    test('parses signals by direction and recursively parses submodules', () {
      final tree = TreeModel.fromJson({
        'name': 'top',
        'inputs': {
          'clock': {'value': "1'h0", 'width': 1},
        },
        'outputs': {
          'result': {'value': "8'h2a", 'width': 8},
        },
        'inouts': {
          'bus': {'value': "4'hf", 'width': 4},
        },
        'subModules': [
          {
            'name': 'child',
            'inputs': <String, dynamic>{},
            'outputs': <String, dynamic>{},
            'subModules': <Map<String, dynamic>>[],
          },
        ],
      });

      expect(tree.name, 'top');
      expect(
        tree.inputs.single.toMap(),
        {'name': 'clock', 'direction': 'Input', 'value': "1'h0", 'width': 1},
      );
      expect(
        tree.outputs.single.toMap(),
        {'name': 'result', 'direction': 'Output', 'value': "8'h2a", 'width': 8},
      );
      expect(
        tree.inouts.single.toMap(),
        {'name': 'bus', 'direction': 'Inout', 'value': "4'hf", 'width': 4},
      );
      expect(tree.subModules.single.name, 'child');
    });

    test('uses no inout signals when the JSON omits them', () {
      final tree = TreeModel.fromJson({
        'name': 'leaf',
        'inputs': <String, dynamic>{},
        'outputs': <String, dynamic>{},
        'subModules': <Map<String, dynamic>>[],
      });

      expect(tree.inouts, isEmpty);
    });
  });
}
