/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// external.dart
/// Definition for external modules
///
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// Represents a [Module] whose definition exists outside of this framework in SystemVerilog.
///
/// This is useful for interacting with SystemVerilog modules.
/// You can add custom behavior for how to synthesize the generated SystemVerilog
/// as well as extend functionality with behavioral models or cosimulation.
abstract class ExternalSystemVerilogModule extends Module
    with CustomSystemVerilog {
  /// The name of the top SystemVerilog module.
  final String topModuleName;

  /// A map of parameter names and values to be passed to the SystemVerilog module.
  final Map<String, String>? parameters;

  ExternalSystemVerilogModule(
      {required this.topModuleName,
      this.parameters,
      String name = 'external_module'})
      : super(
            name: name,
            definitionName: topModuleName,
            reserveDefinitionName: true);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    return SystemVerilogSynthesizer.instantiationVerilogWithParameters(
        this, topModuleName, instanceName, inputs, outputs,
        parameters: parameters, forceStandardInstantiation: true);
  }
}

@Deprecated('Use ExternalSystemVerilogModule instead.')
typedef ExternalModule = ExternalSystemVerilogModule;
