// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// netlist_module_translation.dart
// Per-module state and ordered phases for netlist synthesis.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_cell_mapper.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_validation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// Mutable state for translating one module level into a netlist.
@internal
class NetlistModuleTranslation {
  /// The module being translated.
  final Module module;

  /// The synthesis definition for this module level, when one can be built.
  final NetlistSynthModuleDefinition? synthDef;

  final NetlistCellMapper _netlistCellMapper;
  final bool Function(Module module) _generatesDefinition;
  final String Function(Module module) _getInstanceTypeOfModule;

  /// The next available integer wire identifier.
  int nextId = 2;

  /// Wire identifiers allocated for each synthesis logic.
  final Map<SynthLogic, List<int>> synthLogicIds = {};

  /// Emitted module ports.
  final Map<String, Map<String, Object?>> ports = {};

  /// Emitted cells.
  final Map<String, Map<String, Object?>> cells = {};

  /// Emitted netnames.
  final Map<String, Object?> netnames = {};

  /// Constants consumed only by procedural cells, which need no driver cell.
  final Set<SynthLogic> blockedConstSynthLogics = {};

  /// Creates translation state for one [module].
  NetlistModuleTranslation(
    this.module, {
    required NetlistCellMapper netlistCellMapper,
    required bool Function(Module module) generatesDefinition,
    required String Function(Module module) getInstanceTypeOfModule,
  })  : _netlistCellMapper = netlistCellMapper,
        _generatesDefinition = generatesDefinition,
        _getInstanceTypeOfModule = getInstanceTypeOfModule,
        synthDef = module is SystemVerilog &&
                module.generatedDefinitionType == DefinitionGenerationType.none
            ? null
            : NetlistSynthModuleDefinition(module);

  /// Allocates the next wire identifier.
  int allocateWireId() => nextId++;

  /// Allocates or returns the wire identifiers for [synthLogic].
  List<int> getIds(SynthLogic synthLogic) {
    final resolved = synthLogic.isConstant ? synthLogic : synthLogic.resolved;
    return synthLogicIds.putIfAbsent(
      resolved,
      () => List<int>.generate(resolved.width, (_) => allocateWireId()),
    );
  }

  /// Emits input, output, and inout ports in canonical allocation order.
  void processPorts() {
    final portGroups = [
      ('input', synthDef?.inputs, module.inputs),
      ('output', synthDef?.outputs, module.outputs),
      ('inout', synthDef?.inOuts, module.inOuts),
    ];
    for (final (direction, synthLogics, modulePorts) in portGroups) {
      if (synthLogics != null) {
        for (final synthLogic in synthLogics) {
          final ids = getIds(synthLogic);
          final portName =
              NetlistUtils.portNameForSynthLogic(synthLogic, modulePorts);
          if (portName != null) {
            final portLogic = modulePorts[portName];
            ports[portName] = {
              'direction': direction,
              'bits': ids,
              if (portLogic != null)
                'logic_type': NetlistUtils.buildLogicType(portLogic, ids),
            };
          }
        }
      } else {
        for (final entry in modulePorts.entries) {
          final ids = List<int>.generate(
            entry.value.width,
            (_) => allocateWireId(),
          );
          ports[entry.key] = {
            'direction': direction,
            'bits': ids,
            'logic_type': NetlistUtils.buildLogicType(entry.value, ids),
          };
        }
      }
    }
  }

  /// Preallocates internal wires in [Module.internalSignals] order.
  void processInternalWires() {
    final definition = synthDef;
    if (definition == null) {
      return;
    }
    module.internalSignals
        .map((signal) => definition.logicToSynthMap[signal])
        .whereType<SynthLogic>()
        .where((synthLogic) => !synthLogic.isConstant)
        .forEach(getIds);
  }

  /// Emits cells and removes instances cleared by procedural-port collapsing.
  void processCells() {
    final definition = synthDef;
    if (definition == null) {
      return;
    }

    final emittedCellKeys = <SynthSubModuleInstantiation, String>{};
    for (final instance in definition.subModuleInstantiations) {
      if (!instance.needsInstantiation) {
        continue;
      }

      final submodule = instance.module;
      final isLeaf = !_generatesDefinition(submodule);
      final defaultCellType = isLeaf
          ? submodule.definitionName
          : _getInstanceTypeOfModule(submodule);
      final rawPortDirs = <String, String>{};
      final rawConnections = <String, List<Object>>{};

      for (final (direction, mapping) in [
        ('input', instance.inputMapping),
        ('output', instance.outputMapping),
        ('inout', instance.inOutMapping),
      ]) {
        for (final entry in mapping.entries) {
          rawPortDirs[entry.key] = direction;
          rawConnections[entry.key] = getIds(entry.value).cast<Object>();
        }
      }

      final mapped = isLeaf
          ? _netlistCellMapper.map(submodule, rawPortDirs, rawConnections)
          : null;
      final cellPortDirs = mapped?.portDirs ?? rawPortDirs;
      final cellConnections = mapped?.connections ?? rawConnections;
      final cellKey = instance.name;
      emittedCellKeys[instance] = cellKey;

      if (submodule is Combinational || submodule is Sequential) {
        NetlistUtils.collapseAlwaysBlockPorts(
          definition,
          instance,
          cellPortDirs,
          cellConnections,
          getIds,
        );
        _filterProceduralConstants(
          instance,
          cellPortDirs,
          cellConnections,
        );
        _renameProceduralPorts(
          instance,
          cellPortDirs,
          cellConnections,
        );
      }

      cells[cellKey] = {
        'hide_name': 0,
        'type': mapped?.cellType ?? defaultCellType,
        'parameters': mapped?.parameters ?? <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': cellPortDirs,
        'connections': cellConnections,
      };
    }

    definition.subModuleInstantiations
        .where((instance) => !instance.needsInstantiation)
        .map((instance) => emittedCellKeys[instance])
        .whereType<String>()
        .forEach(cells.remove);
  }

  /// Emits port and internal netnames, fills unnamed connection coverage,
  /// and optionally removes names for undriven wires.
  void processNetnames({
    required List<Object> Function(List<Object> bits) applyAlias,
    required Map<int, int> arraySliceOldToNew,
    required Map<int, int> arrayConcatOldToNew,
    required bool pruneUndriven,
    required Set<int> drivenBits,
  }) {
    final emittedNames = <String>{};
    final isInlineSystemVerilog = module is InlineSystemVerilog;

    void addNetname(
      String name,
      List<Object> bits, {
      bool hideName = false,
      bool computed = false,
      Map<String, Object?>? logicType,
    }) {
      if (!emittedNames.add(name)) {
        return;
      }
      netnames[name] = {
        'bits': bits,
        if (hideName) 'hide_name': 1,
        if (logicType != null) 'logic_type': logicType,
        'attributes': <String, Object?>{
          if (computed || isInlineSystemVerilog) 'computed': 1,
        },
      };
    }

    for (final port in ports.entries) {
      addNetname(
        Sanitizer.sanitizeSV(port.key),
        (port.value['bits']! as List).cast<Object>(),
        logicType: port.value['logic_type'] as Map<String, Object?>?,
      );
    }

    if (synthDef != null) {
      for (final entry in synthLogicIds.entries.where(
        (entry) => !entry.key.isConstant && !entry.key.declarationCleared,
      )) {
        final synthLogic = entry.key;
        final name = NetlistUtils.tryGetSynthLogicName(synthLogic);
        if (name == null) {
          continue;
        }
        var bits = applyAlias(entry.value.cast<Object>());
        if (arraySliceOldToNew.isNotEmpty &&
            synthLogic is SynthLogicArrayElement) {
          bits = [
            for (final bit in bits)
              bit is int ? (arraySliceOldToNew[bit] ?? bit) : bit,
          ];
        }
        if (arrayConcatOldToNew.isNotEmpty &&
            synthLogic is SynthLogicArrayElement) {
          bits = [
            for (final bit in bits)
              bit is int ? (arrayConcatOldToNew[bit] ?? bit) : bit,
          ];
        }
        final typeLogic = NetlistUtils.typeLogicFromSynthLogic(synthLogic);
        addNetname(
          Sanitizer.sanitizeSV(name),
          bits,
          logicType: typeLogic == null
              ? null
              : NetlistUtils.buildLogicType(typeLogic, bits),
        );
      }
    }

    for (final cell in cells.entries.where(
      (entry) => entry.value['type'] == r'$const',
    )) {
      final connections =
          cell.value['connections'] as Map<String, List<Object>>?;
      if (connections != null && connections.isNotEmpty) {
        addNetname(cell.key, connections.values.first, computed: true);
      }
    }

    final coveredIds = netnames.values
        .expand(
          (netname) =>
              ((netname! as Map<String, Object?>)['bits'] as List?) ?? [],
        )
        .whereType<int>()
        .toSet();
    for (final cell in cells.entries) {
      final connections =
          cell.value['connections'] as Map<String, dynamic>? ?? {};
      for (final connection in connections.entries) {
        final missingBits = <Object>[];
        for (final bit in connection.value as List) {
          if (bit is int && coveredIds.add(bit)) {
            missingBits.add(bit);
          }
        }
        if (missingBits.isNotEmpty) {
          addNetname(
            Sanitizer.sanitizeSV('${cell.key}_${connection.key}'),
            missingBits,
            hideName: true,
          );
        }
      }
    }

    if (pruneUndriven) {
      netnames.removeWhere((_, rawNetname) {
        final netname = rawNetname as Map<String, Object?>?;
        final bits = netname?['bits'] as List?;
        if (bits == null) {
          return false;
        }
        final integerBits = bits.whereType<int>();
        return integerBits.isNotEmpty && !integerBits.any(drivenBits.contains);
      });
    }
  }

  /// Separates passthrough outputs and removes dead cells when requested.
  void processCellCleanup({required bool enableDce}) {
    final inputBitIds = ports.values
        .where(
          (port) =>
              port['direction'] == 'input' || port['direction'] == 'inout',
        )
        .expand((port) => port['bits']! as List)
        .whereType<int>()
        .toSet();
    var bufferIndex = 0;
    for (final port in ports.entries.where(
      (entry) => entry.value['direction'] == 'output',
    )) {
      final outputBits = (port.value['bits']! as List).cast<Object>();
      if (!outputBits.any(
        (bit) => bit is int && inputBitIds.contains(bit),
      )) {
        continue;
      }
      final freshBits = List<Object>.generate(
        outputBits.length,
        (_) => allocateWireId(),
      );
      cells['passthrough_buf_$bufferIndex'] = NetlistUtils.makeBufCell(
        outputBits.length,
        outputBits,
        freshBits,
      );
      port.value['bits'] = freshBits;
      bufferIndex++;
    }

    if (!enableDce) {
      return;
    }
    var changed = true;
    while (changed) {
      changed = false;
      final drivenIds = NetlistValidation.connectedBits(
        ports,
        cells,
        portDirections: const {'input', 'inout'},
        cellDirection: 'output',
      );
      final consumedIds = NetlistValidation.connectedBits(
        ports,
        cells,
        portDirections: const {'output', 'inout'},
        cellDirection: 'input',
      );

      cells
        ..removeWhere((_, rawCell) {
          final cell = rawCell as Map<String, dynamic>;
          final connections = cell['connections']! as Map<String, dynamic>;
          final directions = cell['port_directions']! as Map<String, dynamic>;
          final inputPorts = connections.entries.where(
            (port) => directions[port.key] == 'input',
          );
          if (inputPorts.isEmpty) {
            return false;
          }
          final allUndriven = !inputPorts
              .expand((port) => port.value as List)
              .any(
                (bit) =>
                    (bit is int && drivenIds.contains(bit)) || bit is String,
              );
          if (allUndriven) {
            changed = true;
          }
          return allUndriven;
        })
        ..removeWhere((_, rawCell) {
          final cell = rawCell as Map<String, dynamic>;
          final cellType = cell['type'] as String? ?? '';
          if (!cellType.startsWith(r'$')) {
            return false;
          }
          final connections = cell['connections']! as Map<String, dynamic>;
          final directions = cell['port_directions']! as Map<String, dynamic>;
          final outputPorts = connections.entries.where(
            (port) => directions[port.key] == 'output',
          );
          if (outputPorts.isEmpty) {
            return false;
          }
          final allUnconsumed = !outputPorts
              .expand((port) => port.value as List)
              .whereType<int>()
              .any(consumedIds.contains);
          if (allUnconsumed) {
            changed = true;
          }
          return allUnconsumed;
        });
    }
  }

  /// Emits constant driver cells and optionally removes floating constants.
  void processConstants({
    required List<Object> Function(List<Object> bits) applyAlias,
    required bool pruneFloating,
  }) {
    var constantIndex = 0;
    final emittedConstantWires = <int>{};
    for (final entry in synthLogicIds.entries
        .where((entry) => entry.key.isConstant)
        .where((entry) => !blockedConstSynthLogics.contains(entry.key))
        .where((entry) => entry.value.isNotEmpty)) {
      final constant = NetlistUtils.constValueFromSynthLogic(entry.key);
      if (constant == null) {
        continue;
      }
      final resolvedIds = applyAlias(entry.value.cast<Object>());
      final firstWire = resolvedIds.firstWhere(
        (bit) => bit is int,
        orElse: () => -1,
      );
      if (firstWire is int && firstWire >= 0) {
        if (emittedConstantWires.contains(firstWire)) {
          continue;
        }
        emittedConstantWires.addAll(resolvedIds.whereType<int>());
      }

      final valuePart = NetlistUtils.constValuePart(constant);
      final cellName = 'const_${constantIndex}_$valuePart';
      final valueLiteral = valuePart.replaceFirst('_', "'");
      cells[cellName] = {
        'hide_name': 0,
        'type': r'$const',
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': <String, String>{valueLiteral: 'output'},
        'connections': <String, List<Object>>{valueLiteral: resolvedIds},
      };
      constantIndex++;
    }

    if (!pruneFloating) {
      return;
    }
    final consumedIds = NetlistValidation.connectedBits(
      ports,
      cells,
      portDirections: const {'output', 'inout'},
      cellDirection: 'input',
    );
    cells.removeWhere((_, rawCell) {
      final cell = rawCell as Map<String, dynamic>;
      if (cell['type'] != r'$const') {
        return false;
      }
      final connections = cell['connections']! as Map<String, dynamic>;
      final directions = cell['port_directions']! as Map<String, dynamic>;
      return !connections.entries
          .where((port) => directions[port.key] == 'output')
          .expand((port) => port.value as List)
          .whereType<int>()
          .any(consumedIds.contains);
    });
  }

  void _filterProceduralConstants(
    SynthSubModuleInstantiation instance,
    Map<String, String> portDirections,
    Map<String, List<Object>> connections,
  ) {
    final portsToRemove = <String>[];
    for (final port in connections.entries) {
      final synthLogic =
          instance.inputMapping[port.key] ?? instance.inOutMapping[port.key];
      if (synthLogic != null && NetlistUtils.isConstantSynthLogic(synthLogic)) {
        portsToRemove.add(port.key);
        blockedConstSynthLogics.add(synthLogic.resolved);
      }
    }
    for (final portName in portsToRemove) {
      connections.remove(portName);
      portDirections.remove(portName);
    }
  }

  void _renameProceduralPorts(
    SynthSubModuleInstantiation instance,
    Map<String, String> portDirections,
    Map<String, List<Object>> connections,
  ) {
    final renames = <String, String>{};
    for (final portName in connections.keys.toList()) {
      final synthLogic = instance.inputMapping[portName] ??
          instance.outputMapping[portName] ??
          instance.inOutMapping[portName];
      if (synthLogic == null) {
        continue;
      }
      final resolvedName =
          NetlistUtils.tryGetSynthLogicName(synthLogic.resolved);
      if (resolvedName != null && resolvedName != portName) {
        renames[portName] = resolvedName;
      }
    }

    for (final rename in renames.entries) {
      final bits = connections.remove(rename.key)!;
      final direction = portDirections.remove(rename.key)!;
      var newName = rename.value;
      if (connections.containsKey(newName)) {
        newName = '${rename.value}_${rename.key}';
      }
      connections[newName] = bits;
      portDirections[newName] = direction;
    }
  }
}
