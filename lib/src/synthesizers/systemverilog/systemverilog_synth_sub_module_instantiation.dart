// Copyright (C) 2021-2025 Intel Corporation
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

  /// Whether inline expressions should be rendered using [LeafExpressionPlan].
  final bool useLeafExpressionPlanForInlineRendering;

  /// Creates a new [SystemVerilogSynthSubModuleInstantiation] for the given
  /// [module].
  SystemVerilogSynthSubModuleInstantiation(
    super.module, {
    this.useLeafExpressionPlanForInlineRendering = false,
  });

  /// Mapping from [SynthLogic]s which are outputs of inlineable SV to those
  /// inlineable modules.
  Map<SynthLogic, SystemVerilogSynthSubModuleInstantiation>?
      synthLogicToInlineableSynthSubmoduleMap;

  /// Provides the inline SV representation for this module.
  ///
  /// Should only be called if [module] is [InlineSystemVerilog].
  String inlineVerilog() {
    final portNameToValueMapping = modulePortsMapWithInline(
      {...inputMapping, ...inOutMapping}
        ..remove((module as InlineSystemVerilog).resultSignalName),
      synthLogicToInlineableSynthSubmoduleMap,
      (submodule) => submodule.inlineVerilog(),
    );

    assert(
        (module is SystemVerilog &&
                (module as SystemVerilog).acceptsEmptyPortConnections) ||
            portNameToValueMapping.values.none((e) => e.isEmpty),
        'Inline modules should not ever receive empty port values,'
        ' only module instantiations can get something like `.port_name()`.');

    final inlineSvRepresentation = useLeafExpressionPlanForInlineRendering
        ? _leafEmitter.expressionFor(
            module as InlineSystemVerilog,
            portNameToValueMapping,
          )
        : (module as InlineSystemVerilog).inlineVerilog(portNameToValueMapping);

    return '($inlineSvRepresentation)';
  }

  /// Provides the full SV instantiation for this module.
  String? instantiationVerilog(String instanceType) {
    if (!needsInstantiation) {
      return null;
    }
    return SystemVerilogSynthesizer.instantiationVerilogFor(
        module: module,
        instanceType: instanceType,
        instanceName: name,
        ports: modulePortsMapWithInline({
          ...inputMapping,
          ...outputMapping,
          ...inOutMapping,
        }, synthLogicToInlineableSynthSubmoduleMap,
            (submodule) => submodule.inlineVerilog()));
  }
}
