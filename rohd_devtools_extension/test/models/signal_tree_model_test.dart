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
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

void main() {
  group('SignalModel', () {
    test('round trips through the legacy map format', () {
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

    test('exposes occurrence properties', () {
      final signal = SignalModel(
        name: 'accumulator',
        direction: 'output',
        value: "8'h2a",
        width: 8,
      );

      expect(signal.name, 'accumulator');
      expect(signal.direction, 'output');
      expect(signal.value, "8'h2a");
      expect(signal.width, 8);
    });
  });

  group('TreeModel', () {
    test('supports the legacy directional constructor', () {
      final tree = TreeModel(
        name: 'top',
        inputs: [
          SignalModel(
            name: 'clock',
            direction: 'Input',
            value: "1'h0",
            width: 1,
          ),
        ],
        outputs: const [],
        inouts: const [],
        subModules: [TreeModel(name: 'child')],
      );

      expect(tree.inputs.single.name, 'clock');
      expect(tree.subModules.single.name, 'child');
    });

    test('parses the legacy JSON format', () {
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

      expect(tree.inputs.single.toMap(), {
        'name': 'clock',
        'direction': 'Input',
        'value': "1'h0",
        'width': 1,
      });
      expect(tree.outputs.single.toMap(), {
        'name': 'result',
        'direction': 'Output',
        'value': "8'h2a",
        'width': 8,
      });
      expect(tree.inouts.single.toMap(), {
        'name': 'bus',
        'direction': 'Inout',
        'value': "4'hf",
        'width': 4,
      });
      expect(tree.subModules.single.name, 'child');
    });

    test('groups signals by direction and exposes child occurrences', () {
      final tree = TreeModel(
        name: 'top',
        signals: [
          SignalModel(
            name: 'clock',
            direction: 'input',
            value: "1'h0",
            width: 1,
          ),
          SignalModel(
            name: 'result',
            direction: 'output',
            value: "8'h2a",
            width: 8,
          ),
          SignalModel(
            name: 'bus',
            direction: 'inout',
            value: "4'hf",
            width: 4,
          ),
        ],
        children: [TreeModel(name: 'child')],
      );

      expect(tree.name, 'top');
      expect(tree.inputs.single.name, 'clock');
      expect(tree.outputs.single.name, 'result');
      expect(tree.inouts.single.name, 'bus');
      expect(tree.children.single.name, 'child');
    });

    test('uses no inout signals when none are present', () {
      final tree = TreeModel(
        name: 'leaf',
        signals: [SignalModel(name: 'clock', direction: 'input', width: 1)],
      );

      expect(tree.inouts, isEmpty);
    });

    test('legacy adapter preserves inout ports', () {
      final data = DesignDataAdapter.parseJson({
        'name': 'top',
        'inputs': <String, dynamic>{},
        'outputs': <String, dynamic>{},
        'inouts': {
          'bus': {'value': "4'hf", 'width': 4},
        },
        'subModules': <Map<String, dynamic>>[],
      });

      expect(data.hierarchy.root.inouts.single.name, 'bus');
      expect(data.hierarchy.root.inouts.single.width, 4);
    });

    test('UI barrel exports simulation time display', () {
      const display = SimulationTimeDisplay(unit: 'ns');

      expect(display.format(42), '42ns');
    });
  });
}
