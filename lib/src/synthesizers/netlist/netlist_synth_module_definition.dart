// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synth_module_definition.dart
// Synth module definition specialization for netlist synthesis.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A [SynthModuleDefinition] that preserves cells for netlist synthesis.
@internal
class NetlistSynthModuleDefinition extends SynthModuleDefinition {
  /// Creates a netlist synthesis definition for [module].
  NetlistSynthModuleDefinition(Module module) : super(module) {
    // Create explicit $slice cells for LogicArray input ports so the
    // netlist shows select gates for element extraction rather than
    // flat bit aliasing.
    module.inputs.values.whereType<LogicArray>().forEach(
          _subsetReceiveArrayPort,
        );

    // Same for LogicArray outputs on submodules (received into this scope).
    final subModuleOutputArrays = module.subModules
        .expand((sub) => sub.outputs.values)
        .whereType<LogicArray>()
        .toSet()
      ..forEach(_subsetReceiveArrayPort);

    // Create explicit $concat cells for internal LogicArrays whose elements
    // are driven independently (e.g. by constants) and then consumed by
    // submodule input ports. This parallels what _subsetReceiveArrayPort does
    // on the decomposition side.
    //
    // Skip arrays that were merged with a port array's SynthLogic; those are
    // already structurally decomposed by the $slice cells created above.
    // Also skip submodule output arrays that already received $slice cells.
    final portArrays = {
      ...module.inputs.values.whereType<LogicArray>(),
      ...module.outputs.values.whereType<LogicArray>(),
      ...module.inOuts.values.whereType<LogicArray>(),
    };
    final excludedArrays = <LogicArray>{
      ...portArrays,
      ...subModuleOutputArrays,
    };

    void addNestedArrays(LogicArray array) {
      for (final element in array.elements) {
        if (element is LogicArray) {
          excludedArrays.add(element);
          addNestedArrays(element);
        }
      }
    }

    <LogicArray>{
      ...portArrays,
      ...subModuleOutputArrays,
    }.forEach(addNestedArrays);
    final portArraySynthLogics = <SynthLogic>{};
    for (final portArray in excludedArrays) {
      final synthLogic = logicToSynthMap[portArray];
      if (synthLogic != null) {
        portArraySynthLogics.add(synthLogic.resolved);
      }
    }
    module.internalSignals.whereType<LogicArray>().where((signal) {
      if (excludedArrays.contains(signal)) {
        return false;
      }
      final synthLogic = logicToSynthMap[signal];
      if (synthLogic == null) {
        return false;
      }
      return !portArraySynthLogics.contains(synthLogic.resolved);
    }).forEach(_concatAssembleArray);
  }

  /// Adds slice cells that decompose a LogicArray port into element signals.
  void _subsetReceiveArrayPort(LogicArray port) {
    final portSynth = getSynthLogic(port)!;

    var index = 0;
    for (final element in port.elements) {
      final elementSynth = getSynthLogic(element)!;
      internalSignals.add(elementSynth);

      final subsetModule = SynthArraySlice(
        Logic(width: port.width, name: 'DUMMY'),
        index,
        index + element.width - 1,
        destination: element,
      );

      getSynthSubModuleInstantiation(subsetModule)
        ..setOutputMapping(subsetModule.subset.name, elementSynth)
        ..setInputMapping(subsetModule.original.name, portSynth)
        ..pickName(module);

      index += element.width;
    }
  }

  /// Adds a concat cell that assembles independent LogicArray element signals.
  void _concatAssembleArray(LogicArray array) {
    final arraySynth = getSynthLogic(array)!;
    final dummyElements = [
      for (final element in array.elements)
        Logic(width: element.width, name: 'DUMMY'),
    ];

    // Swizzle reverses its inputs, so reverse here to keep in0 aligned with
    // element[0], the least-significant array element.
    final concatModule = SynthArrayConcat(
      dummyElements.reversed.toList(),
      destination: array,
    );
    final instantiation = getSynthSubModuleInstantiation(concatModule)
      ..setOutputMapping(concatModule.out.name, arraySynth);

    for (var index = 0; index < array.elements.length; index++) {
      final elementSynth = getSynthLogic(array.elements[index])!;
      internalSignals.add(elementSynth);
      final inputName = concatModule.inputs.keys.elementAt(index);
      instantiation.setInputMapping(inputName, elementSynth);
    }

    instantiation.pickName(module);
  }

  @override
  void process() {
    // Netlist synthesis preserves every submodule as a cell.
  }
}
