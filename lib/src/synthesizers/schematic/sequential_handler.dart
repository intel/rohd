// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sequential_handler.dart
// Class for handling [Sequential] child modules in the schematic
// dumper. This encapsulates simple-vs-complex mapping and synthetic net
// allocation for mux/dff generation.
//
// 2025 December 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Handler to process [Sequential] child modules in the schematic
/// dumper.
class SequentialHandler {
  /// Creates a [SequentialHandler].
  SequentialHandler();

  /// Process a [Sequential]-type [Module] child, emitting cells and registering
  /// any synthetic nets into [syntheticNets]. Returns true if the child was
  /// processed (and the caller should `continue`), false otherwise.
  bool handleSequential({
    required Module childModule,
    required Map<String, Logic> ports,
    required Map<Logic, List<Object?>> internalNetIds,
    required List<Object?> Function(Logic) idsForChildLogic,
    required Map<String, Map<String, Object?>> cells,
    required Map<String, List<Object?>> syntheticNets,
    required int Function() nextInternalNetIdGetter,
    required void Function(int) nextInternalNetIdSetter,
  }) {
    if (childModule.definitionName != 'Sequential') {
      return false;
    }

    final triggers = <String, Logic>{};
    final dataInputs = <String, Logic>{};
    final dataOutputs = <String, Logic>{};

    for (final port in ports.entries) {
      final name = port.key;
      final logic = port.value;
      if (name.startsWith('_trigger')) {
        triggers[name] = logic;
      } else if (name.startsWith('_in')) {
        dataInputs[name] = logic;
      } else if (name.startsWith('_out')) {
        dataOutputs[name] = logic;
      }
    }

    final cellKey = childModule.hasBuilt
        ? childModule.uniqueInstanceName
        : childModule.name;

    // Simple case: 1 trigger, 1 data input, 1 output.
    if (triggers.length == 1 &&
        dataInputs.length == 1 &&
        dataOutputs.length == 1) {
      final clkLogic = triggers.values.first;
      final dLogic = dataInputs.values.first;
      final qLogic = dataOutputs.values.first;

      final connMap = <String, List<Object?>>{
        'CLK': idsForChildLogic(clkLogic),
        'D': idsForChildLogic(dLogic),
        'Q': idsForChildLogic(qLogic),
      };

      cells[cellKey] = {
        'hide_name': 0,
        'type': r'$dff',
        'parameters': <String, Object?>{
          'CLK_POLARITY': 1,
          'WIDTH': qLogic.width,
        },
        'attributes': <String, Object?>{},
        'port_directions': <String, String>{
          'CLK': 'input',
          'D': 'input',
          'Q': 'output',
        },
        'connections': connMap,
      };
      return true;
    }

    // Complex case: try to synthesize mux + dff
    final clkIds = triggers.isNotEmpty
        ? idsForChildLogic(triggers.values.first)
        : <Object?>[];

    Logic? conditionInput;
    final dataOnlyInputs = <String, Logic>{};
    for (final entry in dataInputs.entries) {
      final name = entry.key;
      if (name.contains('greaterThan') ||
          name.contains('lessThan') ||
          name.contains('equal') ||
          name.contains('_cond') ||
          (name.startsWith('_in0_') && entry.value.width == 1)) {
        conditionInput ??= entry.value;
      } else if (!name.contains('const')) {
        dataOnlyInputs[name] = entry.value;
      }
    }

    if (conditionInput != null && dataOnlyInputs.length >= 2) {
      final dataList = dataOnlyInputs.values.toList();
      final condIds = idsForChildLogic(conditionInput);
      var outputIdx = 0;

      for (final outLogic in dataOutputs.values) {
        final outIds = idsForChildLogic(outLogic);
        final width = outLogic.width;

        final aInput = dataList[outputIdx % dataList.length];
        final bInput = dataList[(outputIdx + 1) % dataList.length];

        final nextIdStart = nextInternalNetIdGetter();
        final muxOutIds = List<Object?>.generate(width, (i) => nextIdStart + i);
        nextInternalNetIdSetter(nextIdStart + width);

        syntheticNets['${cellKey}_mux${outputIdx}_out'] = muxOutIds;

        cells['${cellKey}_mux_$outputIdx'] = {
          'hide_name': 0,
          'type': r'$mux',
          'parameters': <String, Object?>{'WIDTH': width},
          'attributes': <String, Object?>{},
          'port_directions': <String, String>{
            'A': 'input',
            'B': 'input',
            'S': 'input',
            'Y': 'output',
          },
          'connections': <String, List<Object?>>{
            'A': idsForChildLogic(aInput),
            'B': idsForChildLogic(bInput),
            'S': condIds,
            'Y': muxOutIds,
          },
        };

        cells['${cellKey}_dff_$outputIdx'] = {
          'hide_name': 0,
          'type': r'$dff',
          'parameters': <String, Object?>{
            'CLK_POLARITY': 1,
            'WIDTH': width,
          },
          'attributes': <String, Object?>{},
          'port_directions': <String, String>{
            'CLK': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, List<Object?>>{
            'CLK': clkIds,
            'D': muxOutIds,
            'Q': outIds,
          },
        };

        outputIdx++;
      }
      return true;
    }

    // Fallback: emit generic $sequential cell mapping raw ports
    final connMap = <String, List<Object?>>{};
    final portDirs = <String, String>{};
    for (final port in ports.entries) {
      final logic = port.value;
      final dir = logic.isInput
          ? 'input'
          : logic.isOutput
              ? 'output'
              : 'inout';
      portDirs[port.key] = dir;
      final ids = idsForChildLogic(logic);
      if (ids.isNotEmpty) {
        connMap[port.key] = ids;
      }
    }

    cells[cellKey] = {
      'hide_name': 0,
      'type': r'$sequential',
      'parameters': <String, Object?>{'CLK_POLARITY': 1},
      'attributes': <String, Object?>{},
      'port_directions': portDirs,
      'connections': connMap,
    };

    return true;
  }
}
