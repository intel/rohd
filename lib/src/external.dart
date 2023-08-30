// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// external.dart
// Definition for external modules
//
// 2021 May 25
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Represents a [Module] whose definition exists outside of this framework
/// in SystemVerilog.
///
/// This is useful for interacting with SystemVerilog modules. You can add
/// custom behavior for how to synthesize the generated SystemVerilog as well
/// as extend functionality with behavioral models or cosimulation.
abstract class ExternalSystemVerilogModule extends Module
    with CustomSystemVerilog {
  /// A map of parameter names and values to be passed to the SystemVerilog
  /// module.
  final Map<String, String>? parameters;

  /// Constructs an instance of an externally defined SystemVerilog module.
  ///
  /// The name of the SystemVerilog module should match [definitionName]
  /// exactly. The [name] will be the instance name when referred to in
  /// generated SystemVerilog.
  ExternalSystemVerilogModule({
    required String definitionName,
    this.parameters,
    super.name = 'external_module',
  }) : super(definitionName: definitionName, reserveDefinitionName: true);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> inputs, Map<String, String> outputs) =>
      SystemVerilogSynthesizer.instantiationVerilogWithParameters(
          this, definitionName, instanceName, inputs, outputs,
          parameters: parameters, forceStandardInstantiation: true);
}

/// Deprecated - Use [ExternalSystemVerilogModule] instead.
@Deprecated('Use ExternalSystemVerilogModule instead.')
typedef ExternalModule = ExternalSystemVerilogModule;
