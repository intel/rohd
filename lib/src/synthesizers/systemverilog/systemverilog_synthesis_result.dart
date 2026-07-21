// Copyright (C) 2021-2026 Intel Corporation
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
  /// Returns the custom definition artifact for [definitionType].
  BackendArtifact _definitionArtifactFor(String definitionType) =>
      (module as BackendArtifactProvider).artifactFor(
        BackendArtifactContext.definition(
          backend: EmissionBackend.systemVerilog,
          definitionType: definitionType,
        ),
      )!;

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
      _definitionArtifactFor('*PLACEHOLDER*').contents.hashCode;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemVerilogCustomDefinitionSynthesisResult &&
      _definitionArtifactFor('*PLACEHOLDER*').contents ==
          other._definitionArtifactFor('*PLACEHOLDER*').contents;

  @override
  String toFileContents() =>
      _definitionArtifactFor(getInstanceTypeOfModule(module)).contents;

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
            name: instanceTypeName,
            contents: _definitionArtifactFor(getInstanceTypeOfModule(module))
                .contents)
      ]);
}

/// A [SynthesisResult] representing a conversion of a [Module] to
/// SystemVerilog.
class SystemVerilogSynthesisResult extends SynthesisResult {
  /// Configuration controlling generated SystemVerilog.
  final SystemVerilogSynthesizerConfiguration configuration;

  /// A cached copy of the generated ports.
  late final String _portsString;

  /// A cached copy of the generated contents of the module.
  late final String _moduleContentsString;

  /// A cached copy of the generated parameters.
  late final String? _parameterString;

  /// The main [SynthModuleDefinition] for this.
  final SynthModuleDefinition _synthModuleDefinition;

  /// Backend-neutral resolved structure used by this renderer.
  late final ModuleEmissionPlan _emissionPlan;

  @override
  List<Module> get supportingModules =>
      _synthModuleDefinition.supportingModules;

  /// Creates a new [SystemVerilogSynthesisResult] for the given [module].
  SystemVerilogSynthesisResult(
    super.module,
    super.getInstanceTypeOfModule, {
    this.configuration = const SystemVerilogSynthesizerConfiguration(),
  }) : _synthModuleDefinition = SystemVerilogSynthModuleDefinition(
          module,
          configuration: configuration,
        ) {
    _emissionPlan = ModuleEmissionPlan.fromDefinition(_synthModuleDefinition);
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
  Iterable<String> _verilogInputs() => _emissionPlan.inputs.map((sig) {
        assert(module.tryInput(sig.name) != null,
            'Named input ${sig.name} not found in module ${module.name}.');
        return _verilogPort('input', 'wire', sig);
      });

  /// Representation of all output port declarations in generated SV.
  Iterable<String> _verilogOutputs() => _emissionPlan.outputs.map((sig) {
        assert(module.tryOutput(sig.name) != null,
            'Named output ${sig.name} not found in module ${module.name}.');
        return _verilogPort('output', 'var', sig);
      });

  /// Representation of all inout port declarations in generated SV.
  Iterable<String> _verilogInOuts() => _emissionPlan.inOuts.map((sig) {
        assert(module.tryInOut(sig.name) != null,
            'Named inOut ${sig.name} not found in module ${module.name}.');
        return _verilogPort('inout', 'wire', sig);
      });

  /// Representation of a port declaration in generated SV.
  String _verilogPort(String direction, String objectType, SynthLogic sig) => [
        direction,
        if (configuration.portObjectType == SystemVerilogPortType.explicit)
          objectType,
        if (configuration.portDataType == SystemVerilogPortType.explicit)
          'logic',
        sig.definitionName(),
      ].join(' ');

  /// Representation of all internal net declarations in generated SV.
  String _verilogInternalSignals({Set<SynthLogic> excludedSignals = const {}}) {
    final declarations = <String>[];
    for (final sig in _emissionPlan.internalSignals
        .where((e) => e.needsDeclaration && !excludedSignals.contains(e))
        .sorted((a, b) => a.name.compareTo(b.name))) {
      declarations.add('${sig.definitionType()} ${sig.definitionName()};');
    }
    return declarations.join('\n');
  }

  /// Representation of all assignments in generated SV.
  String _verilogAssignments({Set<SynthLogic> excludedSignals = const {}}) {
    final assignmentLines = <String>[];
    String rangeString(int upperIndex, int lowerIndex) =>
        upperIndex == lowerIndex
            ? '[$upperIndex]'
            : '[$upperIndex:$lowerIndex]';

    for (final assignment in _emissionPlan.assignments) {
      if (assignment.src.declarationCleared ||
          assignment.dst.declarationCleared ||
          excludedSignals.contains(assignment.dst.resolved)) {
        continue;
      }

      assert(
          !(assignment.src.isNet && assignment.dst.isNet),
          'Net connections should have been implemented as'
          ' bidirectional net connections.');

      var dstSliceString = '';
      var srcSliceString = '';
      if (assignment is RangeSynthAssignment) {
        dstSliceString = rangeString(
          assignment.dstUpperIndex,
          assignment.dstLowerIndex,
        );
        srcSliceString = rangeString(
          assignment.srcUpperIndex,
          assignment.srcLowerIndex,
        );
      } else if (assignment is PartialSynthAssignment && assignment.width > 1) {
        dstSliceString = rangeString(
          assignment.dstUpperIndex,
          assignment.dstLowerIndex,
        );
      }

      assignmentLines.add('assign ${assignment.dst.name}$dstSliceString'
          ' = ${assignment.src.name}$srcSliceString;');
    }
    return assignmentLines.join('\n');
  }

  /// Representation of all sub-module instantiations in generated SV.
  String _verilogSubModuleInstantiations(
      String Function(Module module) getInstanceTypeOfModule) {
    final subModuleLines = <String>[];
    for (final subModuleInstantiation in _emissionPlan.instances) {
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
    String Function(Module module) getInstanceTypeOfModule,
  ) {
    final subModuleInstantiations =
        _verilogSubModuleInstantiations(getInstanceTypeOfModule);
    final unusedConstantIntermediates =
        _unusedConstantIntermediates(subModuleInstantiations);

    return [
      _verilogInternalSignals(excludedSignals: unusedConstantIntermediates),
      _verilogAssignments(excludedSignals: unusedConstantIntermediates),
      subModuleInstantiations,
    ].where((element) => element.isNotEmpty).join('\n');
  }

  Set<SynthLogic> _unusedConstantIntermediates(String emittedInstances) {
    final assignmentSources = <SynthLogic>{};
    for (final assignment in _emissionPlan.assignments) {
      assignmentSources.add(assignment.src.resolved);
    }

    return {
      for (final assignment in _emissionPlan.assignments)
        if (assignment.src.resolved.isConstant &&
            assignment.dst.resolved is! SynthLogicArrayElement &&
            _emissionPlan.internalSignals.contains(assignment.dst.resolved) &&
            !assignment.dst.resolved.isPort(module) &&
            !assignmentSources.contains(assignment.dst.resolved) &&
            !_emittedTextReferences(
              emittedInstances,
              assignment.dst.resolved.name,
            ))
          assignment.dst.resolved,
    };
  }

  bool _emittedTextReferences(String text, String signalName) => RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(signalName)}(?=[^A-Za-z0-9_]|\$)',
        multiLine: true,
      ).hasMatch(text);

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
