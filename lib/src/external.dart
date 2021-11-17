/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// external.dart
/// Definition for external modules
///
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

// TODO: offer a way to reference sub-module signals

// TODO: add a test for externalmodule

/// Represents a [Module] whose definition exists outside of this framework.
///
/// This is useful for interacting with, for example, SystemVerilog modules.
/// You can add custom behavior for how to synthesize the generated SystemVerilog
/// as well as extend functionality with behavior models or cosimulation.
abstract class ExternalModule extends Module with CustomSystemVerilog {
  final String topModuleName;
  final Map<String, String>? parameters;
  ExternalModule(this.topModuleName,
      {this.parameters, String name = 'external_module'})
      : super(name: name);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    //TODO: how to avoid module name conflicts with generated modules?
    return SystemVerilogSynthesizer.instantiationVerilogWithParameters(
        this, topModuleName, instanceName, inputs, outputs,
        parameters: parameters);
  }
}
