// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synth_sub_module_instantiation.dart
// Definition for SystemCSynthSubModuleInstantiation
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents a submodule instantiation for SystemC.
class SystemCSynthSubModuleInstantiation extends SynthSubModuleInstantiation {
  /// Creates a new [SystemCSynthSubModuleInstantiation] for the given
  /// [module].
  SystemCSynthSubModuleInstantiation(super.module);

  /// If [module] is [InlineSystemVerilog], this will be the [SynthLogic] that
  /// is the `result` of that module. Otherwise, `null`.
  SynthLogic? get inlineResultLogic => module is! InlineSystemVerilog
      ? null
      : (outputMapping[(module as InlineSystemVerilog).resultSignalName] ??
          inOutMapping[(module as InlineSystemVerilog).resultSignalName]);

  /// Mapping from [SynthLogic]s which are outputs of inlineable modules to
  /// those inlineable modules.
  Map<SynthLogic, SystemCSynthSubModuleInstantiation>?
      synthLogicToInlineableSynthSubmoduleMap;

  /// Provides a mapping from ports of this module to a string that can be fed
  /// into that port, which may include inline expressions.
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

    if (m is NotGate) {
      final inVal = inputs.values.first;
      return '~$inVal';
    } else if (m is And2Gate) {
      return '${inputs.values.first} & ${inputs.values.last}';
    } else if (m is Or2Gate) {
      return '${inputs.values.first} | ${inputs.values.last}';
    } else if (m is Xor2Gate) {
      return '${inputs.values.first} ^ ${inputs.values.last}';
    } else if (m is Mux) {
      // Mux has inputs: control, d0, d1 → output: y
      // In SystemC: control ? d1 : d0
      final entries = inputs.entries.toList();
      final control = entries[0].value;
      final d0 = entries[1].value;
      final d1 = entries[2].value;
      return '$control ? $d1 : $d0';
    } else if (m is InlineSystemVerilog) {
      // Fallback: use the verilog inline expression as a reasonable
      // approximation (many operators are identical between SV and C++)
      return m.inlineVerilog(inputs);
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
