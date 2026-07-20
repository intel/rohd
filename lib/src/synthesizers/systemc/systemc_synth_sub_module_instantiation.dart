// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synth_sub_module_instantiation.dart
// Definition for SystemCSynthSubModuleInstantiation
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_leaf_emitter.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents a submodule instantiation for SystemC.
class SystemCSynthSubModuleInstantiation extends SynthSubModuleInstantiation {
  static const _defaultLeafEmitter =
      SystemCLeafEmitter(typeForWidth: _systemCType);

  static String _systemCType(int width) {
    if (width == 1) {
      return 'bool';
    } else if (width <= 64) {
      return 'sc_uint<$width>';
    } else {
      return 'sc_biguint<$width>';
    }
  }

  /// Shared leaf emitter used for inline expression generation.
  SystemCLeafEmitter leafEmitter = _defaultLeafEmitter;

  /// Creates a new [SystemCSynthSubModuleInstantiation] for the given
  /// [module].
  SystemCSynthSubModuleInstantiation(super.module);

  /// If [module] is [InlineSystemVerilog], this is the [SynthLogic] mapped
  /// from its [InlineSystemVerilog.resultSignalName].
  SynthLogic? get inlineResultLogic {
    final m = module;
    if (m is! InlineSystemVerilog) {
      return null;
    }
    return outputMapping[m.resultSignalName] ??
        inOutMapping[m.resultSignalName];
  }

  /// Mapping from [SynthLogic]s which are outputs of inlineable modules to
  /// those inlineable modules.
  Map<SynthLogic, SystemCSynthSubModuleInstantiation>?
      synthLogicToInlineableSynthSubmoduleMap;

  /// Resolves module ports, recursively inlining mapped leaf expressions.
  Map<String, String> _modulePortsMapWithInline(
          Map<String, SynthLogic> plainPorts) =>
      plainPorts.map((name, synthLogic) => MapEntry(
          name,
          synthLogicToInlineableSynthSubmoduleMap?[synthLogic]
                  ?.inlineSystemC() ??
              (synthLogic.declarationCleared ? '' : synthLogic.name)));

  /// Provides the inline SystemC expression for this module.
  ///
  /// Should only be called if [module] is [InlineSystemVerilog].
  String inlineSystemC() {
    final portNameToValueMapping = _modulePortsMapWithInline(
      {...inputMapping, ...inOutMapping}
        ..remove((module as InlineSystemVerilog).resultSignalName),
    );

    final inlineRepresentation =
        _inlineSystemCExpression(portNameToValueMapping);

    return '($inlineRepresentation)';
  }

  /// Generates the inline SystemC expression for the gate module.
  String _inlineSystemCExpression(Map<String, String> inputs) {
    final m = module;

    if (m is InlineSystemVerilog) {
      return leafEmitter.expressionFor(m, inputs);
    }

    throw SynthException('Unsupported inline module type: ${m.runtimeType}');
  }

  /// Provides the full SystemC instantiation for this module as a member
  /// declaration and port binding in the constructor.
  ///
  /// Returns null if this module does not need instantiation.
  String? memberDeclaration(String instanceType) {
    if (!needsInstantiation) {
      return null;
    }
    return '$instanceType $name{"$name"};';
  }

  /// Generates port binding statements for the constructor body.
  String? portBindings() {
    if (!needsInstantiation) {
      return null;
    }
    final bindings = <String>[];
    final allPorts = {...inputMapping, ...outputMapping, ...inOutMapping};
    for (final entry in allPorts.entries) {
      final portName = entry.key;
      final synthLogic = entry.value;
      if (!synthLogic.declarationCleared) {
        bindings.add('$name.$portName(${synthLogic.name});');
      }
    }
    return bindings.join('\n');
  }
}
