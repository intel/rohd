// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synthesis_result.dart
// Definition for SystemVerilogCustomDefinitionSynthesisResult
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Extra utilities on [SynthLogic] to help with SystemVerilog synthesis.
extension on SynthLogic {
  /// Gets the SystemVerilog type for this signal.
  String definitionType() => isNet ? 'wire' : 'logic';
}

/// A [SynthesisResult] representing a [Module] that provides a custom
/// SystemVerilog definition.
class SystemVerilogCustomDefinitionSynthesisResult extends SynthesisResult {
  /// Creates a new [SystemVerilogCustomDefinitionSynthesisResult] for the given
  /// [module].
  SystemVerilogCustomDefinitionSynthesisResult(
      super.module, super.getInstanceTypeOfModule)
      : assert(
            module is SystemVerilog &&
                module.generatedDefinitionType ==
                    DefinitionGenerationType.custom,
            'This should only be used for custom system verilog definitions.');

  @override
  int get matchHashCode =>
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!.hashCode;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemVerilogCustomDefinitionSynthesisResult &&
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')! ==
          (other.module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!;

  @override
  String toFileContents() => (module as SystemVerilog)
      .definitionVerilog(getInstanceTypeOfModule(module))!;

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
            name: instanceTypeName,
            contents: (module as SystemVerilog)
                .definitionVerilog(getInstanceTypeOfModule(module))!)
      ]);
}

/// A [SynthesisResult] representing a conversion of a [Module] to
/// SystemVerilog.
class SystemVerilogSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports.
  late final String _portsString;

  /// A cached copy of the generated contents of the module.
  late final String _moduleContentsString;

  /// A cached copy of the generated parameters.
  late final String? _parameterString;

  /// The main [SynthModuleDefinition] for this.
  final SynthModuleDefinition _synthModuleDefinition;

  @override
  List<Module> get supportingModules =>
      _synthModuleDefinition.supportingModules;

  /// Creates a new [SystemVerilogSynthesisResult] for the given [module].
  SystemVerilogSynthesisResult(super.module, super.getInstanceTypeOfModule)
      : _synthModuleDefinition = SystemVerilogSynthModuleDefinition(module) {
    _portsString = _verilogPorts();
    _moduleContentsString = _verilogModuleContents(getInstanceTypeOfModule);
    _parameterString = _verilogParameters(module);
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemVerilogSynthesisResult &&
      other._portsString == _portsString &&
      other._parameterString == _parameterString &&
      other._moduleContentsString == _moduleContentsString;

  @override
  int get matchHashCode =>
      _portsString.hashCode ^
      _moduleContentsString.hashCode ^
      _parameterString.hashCode;

  @override
  String toFileContents() => _toVerilog();

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
          name: instanceTypeName,
          description: 'SystemVerilog module definition for $instanceTypeName',
          contents: _toVerilog(),
        )
      ]);

  /// Representation of all input port declarations in generated SV.
  List<String> _verilogInputs() {
    final declarations = _synthModuleDefinition.inputs
        .map((sig) => 'input ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all output port declarations in generated SV.
  List<String> _verilogOutputs() {
    final declarations = _synthModuleDefinition.outputs
        .map((sig) => 'output ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all inout port declarations in generated SV.
  List<String> _verilogInOuts() {
    final declarations = _synthModuleDefinition.inOuts
        .map((sig) => 'inout ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all internal net declarations in generated SV.
  String _verilogInternalSignals() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalSignals
        .sorted((a, b) => a.name.compareTo(b.name))) {
      if (sig.needsDeclaration) {
        declarations.add('${sig.definitionType()} ${sig.definitionName()};');
      }
    }
    return declarations.join('\n');
  }

  /// Representation of all assignments in generated SV.
  String _verilogAssignments() {
    final assignmentLines = <String>[];
    for (final assignment in _synthModuleDefinition.assignments) {
      assert(
          !(assignment.src.isNet && assignment.dst.isNet),
          'Net connections should have been implemented as'
          ' bidirectional net connections.');

      var sliceString = '';
      if (assignment is PartialSynthAssignment) {
        sliceString = assignment.dstUpperIndex == assignment.dstLowerIndex
            ? '[${assignment.dstUpperIndex}]'
            : '[${assignment.dstUpperIndex}:${assignment.dstLowerIndex}]';
      }

      assignmentLines.add('assign ${assignment.dst.name}$sliceString'
          ' = ${assignment.src.name};');
    }
    return assignmentLines.join('\n');
  }

  /// Representation of all sub-module instantiations in generated SV.
  String _verilogSubModuleInstantiations(
      String Function(Module module) getInstanceTypeOfModule) {
    final subModuleLines = <String>[];
    for (final subModuleInstantiation
        in _synthModuleDefinition.moduleToSubModuleInstantiationMap.values) {
      final instanceType =
          getInstanceTypeOfModule(subModuleInstantiation.module);

      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      final instantiationVerilog =
          subModuleInstantiation.instantiationVerilog(instanceType);
      if (instantiationVerilog != null) {
        subModuleLines.add(instantiationVerilog);
      }
    }
    return subModuleLines.join('\n');
  }

  /// The contents of this module converted to SystemVerilog without module
  /// declaration, ports, etc.
  String _verilogModuleContents(
          String Function(Module module) getInstanceTypeOfModule) =>
      [
        _verilogInternalSignals(),
        _verilogAssignments(), // order matters!
        _verilogSubModuleInstantiations(getInstanceTypeOfModule),
      ].where((element) => element.isNotEmpty).join('\n');

  /// The representation of all port declarations.
  String _verilogPorts() => [
        ..._verilogInputs(),
        ..._verilogOutputs(),
        ..._verilogInOuts(),
      ].join(',\n');

  String? _verilogParameters(Module module) {
    if (module is SystemVerilog) {
      final defParams = module.definitionParameters;
      if (defParams == null || defParams.isEmpty) {
        return null;
      }

      return [
        '#(',
        defParams
            .map((p) => 'parameter ${p.type} ${p.name} = ${p.defaultValue}')
            .join(',\n'),
        ')',
      ].join('\n');
    }

    return null;
  }

  /// The full SV representation of this module.
  String _toVerilog() {
    final verilogModuleName = getInstanceTypeOfModule(module);
    return [
      [
        'module $verilogModuleName',
        _parameterString,
        '(',
      ].nonNulls.join(' '),
      _portsString,
      ');',
      _moduleContentsString,
      'endmodule : $verilogModuleName'
    ].join('\n');
  }
}
