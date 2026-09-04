// Copyright (C) 2021-2026 Intel Corporation
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
  /// Configuration controlling generated SystemVerilog.
  final SystemVerilogSynthesizerConfiguration configuration;

  /// Creates a SystemVerilog synthesizer with the specified [configuration].
  SystemVerilogSynthesizer({
    this.configuration = const SystemVerilogSynthesizerConfiguration(),
  });

  @override
  bool generatesDefinition(Module module) =>
      // ignore: deprecated_member_use_from_same_package - backwards compatibility with CustomSystemVerilog
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
  static String instantiationVerilogFor({
    required Module module,
    required String instanceType,
    required String instanceName,
    required Map<String, String> ports,
    Map<String, String>? parameters,
    bool forceStandardInstantiation = false,
    Map<String, int>? outputPortColumns,
  }) {
    if (!forceStandardInstantiation) {
      if (module is SystemVerilog) {
        return module.instantiationVerilog(instanceType, instanceName, ports) ??
            instantiationVerilogFor(
              module: module,
              instanceType: instanceType,
              instanceName: instanceName,
              ports: ports,
              outputPortColumns: outputPortColumns,
              forceStandardInstantiation: true,
            );
      }
      // ignore: deprecated_member_use_from_same_package - backwards compatibility with CustomSystemVerilog
      else if (module is CustomSystemVerilog) {
        return module.instantiationVerilog(
          instanceType,
          instanceName,
          Map.fromEntries(
            ports.entries.where(
              (element) => module.inputs.containsKey(element.key),
            ),
          ),
          Map.fromEntries(
            ports.entries.where(
              (element) => module.outputs.containsKey(element.key),
            ),
          ),
        );
      }
    }

    //non-custom needs more details
    final connections = <String>[];
    final outputNames = module.outputs.keys.toSet();

    var parameterString = '';
    if (parameters != null && parameters.isNotEmpty) {
      final parameterContents =
          parameters.entries.map((e) => '.${e.key}(${e.value})').join(',');
      parameterString = '#($parameterContents)';
    }

    final prefix = '$instanceType $parameterString $instanceName(';
    var offset = prefix.length;

    void addConnection(String signalName) {
      if (connections.isNotEmpty) {
        offset++;
      }
      final wireValue = ports[signalName]!;
      final connection = '.$signalName($wireValue)';
      if (outputPortColumns != null &&
          outputNames.contains(signalName) &&
          wireValue.isNotEmpty) {
        outputPortColumns[wireValue] = offset + signalName.length + 3;
      }
      connections.add(connection);
      offset += connection.length;
    }

    module.inputs.keys.forEach(addConnection);
    module.outputs.keys.forEach(addConnection);
    module.inOuts.keys.forEach(addConnection);

    final connectionsStr = connections.join(',');

    return '$prefix$connectionsStr);';
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
    Map<String, String> outputs, {
    Map<String, String> inOuts = const {},
    Map<String, String>? parameters,
    bool forceStandardInstantiation = false,
  }) =>
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
    Module module,
    String Function(Module module) getInstanceTypeOfModule,
  ) {
    assert(
      module is! SystemVerilog ||
          module.generatedDefinitionType != DefinitionGenerationType.none,
      'SystemVerilog modules synthesized must generate a definition.',
    );

    return module is SystemVerilog &&
            module.generatedDefinitionType == DefinitionGenerationType.custom
        ? SystemVerilogCustomDefinitionSynthesisResult(
            module,
            getInstanceTypeOfModule,
          )
        : SystemVerilogSynthesisResult(
            module,
            getInstanceTypeOfModule,
            configuration: configuration,
          );
  }
}
