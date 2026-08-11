// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synth_sub_module_instantiation.dart
// Definition for SystemVerilogSynthSubModuleInstantiation
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_leaf_emitter.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents a submodule instantiation for SystemVerilog.
class SystemVerilogSynthSubModuleInstantiation
    extends SynthSubModuleInstantiation {
  static const _leafEmitter = SystemVerilogLeafEmitter();

  /// Creates a new [SystemVerilogSynthSubModuleInstantiation] for the given
  /// [module].
  SystemVerilogSynthSubModuleInstantiation(super.module);

  /// Mapping from [SynthLogic]s which are outputs of inlineable SV to those
  /// inlineable modules.
  Map<SynthLogic, SystemVerilogSynthSubModuleInstantiation>?
      synthLogicToInlineableSynthSubmoduleMap;

  /// Provides the inline SV representation for this module.
  ///
  /// Should only be called if [module] is [InlineLeaf].
  String inlineVerilog() {
    final portNameToValueMapping = modulePortsMapWithInline(
      {...inputMapping, ...inOutMapping}
        ..remove((module as InlineLeaf).resultSignalName),
      synthLogicToInlineableSynthSubmoduleMap,
      (submodule) => submodule.inlineVerilog(),
    );

    assert(
        (module is SystemVerilog &&
                (module as SystemVerilog).acceptsEmptyPortConnections) ||
            module is Swizzle ||
            portNameToValueMapping.values.none((e) => e.isEmpty),
        'Inline modules should not ever receive empty port values,'
        ' only module instantiations can get something like `.port_name()`.');

    final inlineSvRepresentation = _leafEmitter.expressionFor(
      module as InlineLeaf,
      portNameToValueMapping,
    );

    return inlineSvRepresentation.isEmpty ? '' : '($inlineSvRepresentation)';
  }

  /// Provides the full SV instantiation for this module.
  String? instantiationVerilog(String instanceType) {
    if (!needsInstantiation) {
      return null;
    }
    final ports = modulePortsMapWithInline({
      ...inputMapping,
      ...outputMapping,
      ...inOutMapping,
    }, synthLogicToInlineableSynthSubmoduleMap,
        (submodule) => submodule.inlineVerilog());

    for (final entry in inOutMapping.entries) {
      final portValue = ports[entry.key];
      final inlineSubModule =
          synthLogicToInlineableSynthSubmoduleMap?[entry.value] ??
              synthLogicToInlineableSynthSubmoduleMap?[entry.value.resolved];
      final aggregateLvalue = inlineSubModule == null
          ? null
          : _declaredSwizzleAggregateReference(inlineSubModule);
      if (portValue != null &&
          portValue.contains("'bz") &&
          inlineSubModule?.module is Swizzle &&
          aggregateLvalue != null) {
        ports[entry.key] = aggregateLvalue;
      }
    }

    if (module is InlineLeaf) {
      final resultName = (module as InlineLeaf).resultSignalName;
      final resultLogic = inlineResultLogic;
      if (resultLogic == null || !resultLogic.hasName) {
        return null;
      }
      ports[resultName] = resultLogic.name;
    }
    return SystemVerilogSynthesizer.instantiationVerilogFor(
        module: module,
        instanceType: instanceType,
        instanceName: name,
        ports: ports);
  }

  String? _declaredSwizzleAggregateReference(
    SystemVerilogSynthSubModuleInstantiation swizzle,
  ) {
    final result = swizzle.inlineResultLogic;
    if (result == null) {
      return null;
    }

    final mappedInputs = [
      ...swizzle.inputMapping.values,
      ...swizzle.inOutMapping.entries
          .where(
            (entry) =>
                entry.key != (swizzle.module as InlineLeaf).resultSignalName,
          )
          .map((entry) => entry.value),
    ];
    final parentArrays = <SynthLogic>{};
    for (final input in mappedInputs) {
      final element = input is SynthLogicArrayElement
          ? input
          : input.resolved is SynthLogicArrayElement
              ? input.resolved as SynthLogicArrayElement
              : null;
      if (element == null) {
        return null;
      }
      parentArrays.add(element.parentArray.resolved);
    }
    final parentArray = parentArrays.singleOrNull;
    if (parentArray == null ||
        parentArray.width != result.width ||
        !parentArray.needsDeclaration ||
        !parentArray.parentSynthModuleDefinition.internalSignals
            .contains(parentArray)) {
      return null;
    }

    return parentArray.width > 1
        ? '(${parentArray.name}[${parentArray.width - 1}:0])'
        : parentArray.name;
  }
}
