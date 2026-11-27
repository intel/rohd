// Copyright (C) 2021-2026 Intel Corporation
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
abstract class ExternalSystemVerilogModule extends Module with SystemVerilog {
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

  /// Constructs an instance of an externally defined SystemVerilog module
  /// without needing to declare a new subclass.
  ///
  /// The module is named [definitionName] in SystemVerilog and is instantiated
  /// with the given [parameters]. Each entry in [inputs] connects the [Logic]
  /// to an input port of the same name, taking the width from the [Logic]. Each
  /// entry in [outputs] adds an output port whose width is the value. Use
  /// [Module.output] on the returned module to access the output ports.
  ///
  /// ```dart
  /// final mod = ExternalSystemVerilogModule.simple(
  ///   definitionName: 'my_adder',
  ///   inputs: {'a': a, 'b': b},
  ///   outputs: {'sum': 9},
  ///   parameters: {'WIDTH': '8'},
  /// );
  /// final sum = mod.output('sum');
  /// ```
  factory ExternalSystemVerilogModule.simple({
    required String definitionName,
    Map<String, Logic> inputs,
    Map<String, int> outputs,
    Map<String, String>? parameters,
    String name,
  }) = _SimpleExternalSystemVerilogModule;

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) =>
      SystemVerilogSynthesizer.instantiationVerilogFor(
        module: this,
        instanceType: definitionName,
        instanceName: instanceName,
        ports: ports,
        parameters: parameters,
        forceStandardInstantiation: true,
      );
}

/// An [ExternalSystemVerilogModule] whose ports are all declared at
/// construction, used by [ExternalSystemVerilogModule.simple].
class _SimpleExternalSystemVerilogModule extends ExternalSystemVerilogModule {
  _SimpleExternalSystemVerilogModule({
    required super.definitionName,
    Map<String, Logic> inputs = const {},
    Map<String, int> outputs = const {},
    super.parameters,
    super.name,
  }) {
    for (final input in inputs.entries) {
      addInput(input.key, input.value, width: input.value.width);
    }
    for (final output in outputs.entries) {
      addOutput(output.key, width: output.value);
    }
  }
}
