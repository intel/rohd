// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_mixins.dart
// Definition for SystemVerilog Mixins and supporting stuff
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Represents the definition of a SystemVerilog parameter at the time of
/// declaration of a module definition.
class SystemVerilogParameterDefinition {
  /// The SystemVerilog type to use for declaring this parameter.
  final String type;

  /// The default value for this parameter.
  final String defaultValue;

  /// The name of the parameter.
  final String name;

  /// Creates a new SystemVerilog parameter definition with [name] of the
  /// provided [type] with the [defaultValue].
  const SystemVerilogParameterDefinition(this.name,
      {required this.type, required this.defaultValue});
}

/// Allows a [Module] to control the instantiation and/or definition of
/// generated SystemVerilog for that module.
mixin SystemVerilog on Module {
  /// Generates custom SystemVerilog to be injected in place of a `module`
  /// instantiation.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively of the module that would have been instantiated had it not
  /// been overridden.  [ports] is a mapping from the [Module]'s port names to
  /// the names of the signals that are passed into those ports in the generated
  /// SystemVerilog.
  ///
  /// If a standard instantiation is desired, either return `null` or use
  /// [SystemVerilogSynthesizer.instantiationVerilogFor] with
  /// `forceStandardInstantiation` set to `true`.  By default, `null` is
  /// returned and thus a standard instantiation is used.
  String? instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) =>
      null;

  /// A list of names of [input]s which should not have any SystemVerilog
  /// expressions (including constants) in-lined into them. Only signal names
  /// will be fed into these.
  final List<String> expressionlessInputs = const [];

  /// A custom SystemVerilog definition to be produced for this [Module].
  ///
  /// If an empty string is returned (the default behavior), then no definition
  /// will be generated.
  ///
  /// If `null` is returned, then a default definition will be generated.
  ///
  /// This function should have no side effects and always return the same thing
  /// for the same inputs.
  String? definitionVerilog(String definitionType) => '';

  /// A collection of SystemVerilog [SystemVerilogParameterDefinition]s to be
  /// declared on the definition when generating SystemVerilog for this [Module]
  /// if [generatedDefinitionType] is [DefinitionGenerationType.standard].
  ///
  /// If `null` is returned (the default), then no parameters will be generated.
  /// Otherwise, this function should have no side effects and always return the
  /// same thing for the same inputs.
  List<SystemVerilogParameterDefinition>? get definitionParameters => null;

  /// What kind of SystemVerilog definition this [Module] generates, or whether
  /// it does at all.
  ///
  /// By default, this is automatically calculated based on the return value of
  /// [definitionVerilog].
  DefinitionGenerationType get generatedDefinitionType {
    final def = definitionVerilog('*PLACEHOLDER*');
    if (def == null) {
      return DefinitionGenerationType.standard;
    } else if (def.isNotEmpty) {
      return DefinitionGenerationType.custom;
    } else {
      return DefinitionGenerationType.none;
    }
  }
}

/// A type of generation for generated outputs.
enum DefinitionGenerationType {
  /// No definition will be generated.
  none,

  /// A standard definition will be generated.
  standard,

  /// A custom definition will be generated.
  custom,
}

/// Allows a [Module] to define a special type of [SystemVerilog] which can be
/// inlined within other SystemVerilog code.
///
/// The inline SystemVerilog will get parentheses wrapped around it and then
/// dropped into other code in the same way a variable name is.
mixin InlineSystemVerilog on Module implements SystemVerilog {
  /// Generates custom SystemVerilog to be injected in place of the output
  /// port's corresponding signal name.
  ///
  /// The [inputs] are a mapping from the [Module]'s port names to the names of
  /// the signals that are passed into those ports in the generated
  /// SystemVerilog. It will only contain [input]s and [inOut]s, as there should
  /// only be one [output] (named [resultSignalName]) which is driven by the
  /// expression.
  ///
  /// The output will be appropriately wrapped with parentheses to guarantee
  /// proper order of operations.
  String inlineVerilog(Map<String, String> inputs);

  /// The name of the [output] (or [inOut]) port which can be the in-lined
  /// symbol.
  ///
  /// By default, this assumes one [output] port. This should be overridden in
  /// classes which have an [inOut] port as the in-lined symbol.
  String get resultSignalName {
    if (outputs.keys.length != 1) {
      throw Exception('Inline verilog expected to have exactly one output,'
          ' but saw $outputs.');
    }

    return outputs.keys.first;
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    final result = ports[resultSignalName];
    final inputPorts = Map.fromEntries(
      ports.entries.where((element) =>
          inputs.containsKey(element.key) ||
          (inOuts.containsKey(element.key) && element.key != resultSignalName)),
    );
    final inline = inlineVerilog(inputPorts);
    return 'assign $result = $inline;  // $instanceName';
  }

  @override
  @protected
  final List<String> expressionlessInputs = const [];

  @override
  String? definitionVerilog(String definitionType) => '';

  @override
  DefinitionGenerationType get generatedDefinitionType =>
      DefinitionGenerationType.none;

  @override
  List<SystemVerilogParameterDefinition>? get definitionParameters => null;
}

/// Allows a [Module] to define a custom implementation of SystemVerilog to be
/// injected in generated output instead of instantiating a separate `module`.
@Deprecated('Use `SystemVerilog` instead')
mixin CustomSystemVerilog on Module {
  /// Generates custom SystemVerilog to be injected in place of a `module`
  /// instantiation.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively of the module that would have been instantiated had it not
  /// been overridden.  The [Map]s [inputs] and [outputs] are a mapping from the
  /// [Module]'s port names to the names of the signals that are passed into
  /// those ports in the generated SystemVerilog.
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs);

  /// A list of names of [input]s which should not have any SystemVerilog
  /// expressions (including constants) in-lined into them. Only signal names
  /// will be fed into these.
  final List<String> expressionlessInputs = const [];
}
