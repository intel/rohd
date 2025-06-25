// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synthesizer.dart
// Definition for SystemVerilog Synthesizer
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synthesis_result.dart';

/// A [Synthesizer] which generates equivalent SystemVerilog as the
/// given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible.
class SystemVerilogSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) =>
      // ignore: deprecated_member_use_from_same_package
      !((module is CustomSystemVerilog) ||
          (module is SystemVerilog &&
              module.generatedDefinitionType == DefinitionGenerationType.none));

  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name
  /// [instanceName].
  ///
  /// [ports] maps [module] input/output/inout names to a verilog signal name.
  ///
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [ports] should be:
  /// ports:  `{ 'a' : 'sig_a', 'b' : 'sig_b', 'c' : 'sig_c'}`
  ///
  /// If [forceStandardInstantiation] is set, then the standard instantiation
  /// for SystemVerilog modules will be used.
  ///
  /// If [parameters] is provided, then the module will be instantiated with
  /// all of the keys as parameter names set to the corresponding values
  /// provided.
  static String instantiationVerilogFor(
      {required Module module,
      required String instanceType,
      required String instanceName,
      required Map<String, String> ports,
      Map<String, String>? parameters,
      bool forceStandardInstantiation = false}) {
    if (!forceStandardInstantiation) {
      if (module is SystemVerilog) {
        return module.instantiationVerilog(
              instanceType,
              instanceName,
              ports,
            ) ??
            instantiationVerilogFor(
                module: module,
                instanceType: instanceType,
                instanceName: instanceName,
                ports: ports,
                forceStandardInstantiation: true);
      }
      // ignore: deprecated_member_use_from_same_package
      else if (module is CustomSystemVerilog) {
        return module.instantiationVerilog(
          instanceType,
          instanceName,
          Map.fromEntries(ports.entries
              .where((element) => module.inputs.containsKey(element.key))),
          Map.fromEntries(ports.entries
              .where((element) => module.outputs.containsKey(element.key))),
        );
      }
    }

    //non-custom needs more details
    final connections = <String>[];

    for (final signalName in module.inputs.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
    }

    for (final signalName in module.outputs.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
    }

    for (final signalName in module.inOuts.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
    }

    final connectionsStr = connections.join(',');

    var parameterString = '';
    if (parameters != null && parameters.isNotEmpty) {
      final parameterContents =
          parameters.entries.map((e) => '.${e.key}(${e.value})').join(',');
      parameterString = '#($parameterContents)';
    }

    return '$instanceType $parameterString $instanceName($connectionsStr);';
  }

  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name
  /// [instanceName].
  ///
  /// [inputs] and [outputs] map `module` input/output name to a verilog signal
  /// name.
  ///
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [inputs] and [outputs] should be:
  /// inputs:  `{ 'a' : 'sig_a', 'b' : 'sig_b'}`
  /// outputs: `{ 'c' : 'sig_c' }`
  @Deprecated('Use `instantiationVerilogFor` instead.')
  static String instantiationVerilogWithParameters(
          Module module,
          String instanceType,
          String instanceName,
          Map<String, String> inputs,
          Map<String, String> outputs,
          {Map<String, String> inOuts = const {},
          Map<String, String>? parameters,
          bool forceStandardInstantiation = false}) =>
      instantiationVerilogFor(
        module: module,
        instanceType: instanceType,
        instanceName: instanceName,
        ports: {...inputs, ...outputs, ...inOuts},
        parameters: parameters,
        forceStandardInstantiation: forceStandardInstantiation,
      );

  @override
  SynthesisResult synthesize(
      Module module, String Function(Module module) getInstanceTypeOfModule) {
    assert(
        module is! SystemVerilog ||
            module.generatedDefinitionType != DefinitionGenerationType.none,
        'SystemVerilog modules synthesized must generate a definition.');

    return module is SystemVerilog &&
            module.generatedDefinitionType == DefinitionGenerationType.custom
        ? SystemVerilogCustomDefinitionSynthesisResult(
            module, getInstanceTypeOfModule)
        : SystemVerilogSynthesisResult(module, getInstanceTypeOfModule);
  }
}
