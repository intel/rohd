// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synth_sub_module_instantiation.dart
// Definition for SystemVerilogSynthSubModuleInstantiation
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents a submodule instantiation for SystemVerilog.
class SystemVerilogSynthSubModuleInstantiation
    extends SynthSubModuleInstantiation {
  /// If [module] is [InlineSystemVerilog], this will be the [SynthLogic] that
  /// is the `result` of that module.  Otherwise, `null`.
  SynthLogic? get inlineResultLogic => module is! InlineSystemVerilog
      ? null
      : (outputMapping[(module as InlineSystemVerilog).resultSignalName] ??
          inOutMapping[(module as InlineSystemVerilog).resultSignalName]);

  /// Creates a new [SystemVerilogSynthSubModuleInstantiation] for the given
  /// [module].
  SystemVerilogSynthSubModuleInstantiation(super.module);

  /// Mapping from [SynthLogic]s which are outputs of inlineable SV to those
  /// inlineable modules.
  Map<SynthLogic, SystemVerilogSynthSubModuleInstantiation>?
      synthLogicToInlineableSynthSubmoduleMap;

  /// Provides a mapping from ports of this module to a string that can be fed
  /// into that port, which may include inline SV modules as well.
  Map<String, String> _modulePortsMapWithInline(
          Map<String, SynthLogic> plainPorts) =>
      plainPorts.map((name, synthLogic) => MapEntry(
          name,
          synthLogicToInlineableSynthSubmoduleMap?[synthLogic]
                  ?.inlineVerilog() ??
              synthLogic.name));

  /// Provides the inline SV representation for this module.
  ///
  /// Should only be called if [module] is [InlineSystemVerilog].
  String inlineVerilog() {
    final inlineSvRepresentation =
        (module as InlineSystemVerilog).inlineVerilog(
      _modulePortsMapWithInline({...inputMapping, ...inOutMapping}
        ..remove((module as InlineSystemVerilog).resultSignalName)),
    );

    return '($inlineSvRepresentation)';
  }

  /// Provides the full SV instantiation for this module.
  String? instantiationVerilog(String instanceType) {
    if (!needsDeclaration) {
      return null;
    }
    return SystemVerilogSynthesizer.instantiationVerilogFor(
        module: module,
        instanceType: instanceType,
        instanceName: name,
        ports: _modulePortsMapWithInline({
          ...inputMapping,
          ...outputMapping,
          ...inOutMapping,
        }));
  }
}
