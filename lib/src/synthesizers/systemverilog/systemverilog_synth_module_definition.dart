// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synth_module_definition.dart
// Definition for SystemVerilogSynthModuleDefinition
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A special [SynthModuleDefinition] for SystemVerilog modules.
class SystemVerilogSynthModuleDefinition extends SynthModuleDefinition {
  /// Creates a new [SystemVerilogSynthModuleDefinition] for the given [module].
  SystemVerilogSynthModuleDefinition(super.module);

  @override
  void process() {
    _replaceNetConnections();
    _collapseChainableModules();
    _replaceInOutConnectionInlineableModules();
  }

  @override
  SynthSubModuleInstantiation createSubModuleInstantiation(Module m) =>
      SystemVerilogSynthSubModuleInstantiation(m);

  /// Creates a new [_NetConnect] module to synthesize assignment between two
  /// [LogicNet]s.
  SystemVerilogSynthSubModuleInstantiation _addNetConnect(
      SynthLogic dst, SynthLogic src) {
    // make an (unconnected) module representing the assignment
    final netConnect =
        _NetConnect(LogicNet(width: dst.width), LogicNet(width: src.width));

    // instantiate the module within the definition
    final netConnectSynthSubModInst =
        (getSynthSubModuleInstantiation(netConnect)
            as SystemVerilogSynthSubModuleInstantiation)

          // map inouts to the appropriate `_SynthLogic`s
          ..setInOutMapping(_NetConnect.n0Name, dst)
          ..setInOutMapping(_NetConnect.n1Name, src);

    // notify the `SynthBuilder` that it needs declaration
    supportingModules.add(netConnect);

    return netConnectSynthSubModInst;
  }

  /// Replace all [assignments] between two [LogicNet]s with a [_NetConnect].
  void _replaceNetConnections() {
    final reducedAssignments = <SynthAssignment>[];

    for (final assignment in assignments) {
      if (assignment.src.isNet && assignment.dst.isNet) {
        assert(assignment is! PartialSynthAssignment,
            'Net connections should not be partial assignments.');

        _addNetConnect(assignment.dst, assignment.src);
      } else {
        reducedAssignments.add(assignment);
      }
    }

    // only swap them if we actually did anything
    if (assignments.length != reducedAssignments.length) {
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }

  /// Collapses chainable, inlineable modules.
  void _collapseChainableModules() {
    // collapse multiple lines of in-line assignments into one where they are
    // unnamed one-liners
    //  for example, be capable of creating lines like:
    //      assign x = a & b & c & _d_and_e
    //      assign _d_and_e = d & e
    //      assign y = _d_and_e

    // Also feed collapsed chained modules into other modules
    // Need to consider order of operations in systemverilog or else add ()
    // everywhere! (for now add the parentheses)

    // Algorithm:
    //  - find submodule instantiations that are inlineable
    //  - filter to those who only output as input to one other module
    //  - pass an override to the submodule instantiation that the corresponding
    //    input should map to the output of another submodule instantiation
    // do not collapse if signal feeds to multiple inputs of other modules

    final inlineableSubmoduleInstantiations = module.subModules
        .whereType<InlineSystemVerilog>()
        .map((m) => getSynthSubModuleInstantiation(m)
            as SystemVerilogSynthSubModuleInstantiation);

    // number of times each signal name is used by any module
    final signalUsage = <SynthLogic, int>{};

    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final inSynthLogic in [
        ...subModuleInstantiation.inputMapping.values,
        ...subModuleInstantiation.inOutMapping.values
      ]) {
        if (inputs.contains(inSynthLogic) || inOuts.contains(inSynthLogic)) {
          // dont worry about inputs to THIS module
          continue;
        }

        subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

        if (subModuleInstantiation.inlineResultLogic == inSynthLogic) {
          // don't worry about the result signal
          continue;
        }

        signalUsage.update(
          inSynthLogic,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final singleUseSignals = <SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      // don't collapse if:
      //  - used more than once
      //  - inline modules for preferred names
      if (signalUsageCount == 1 && signal.mergeable) {
        singleUseSignals.add(signal);
      }
    });

    // partial assignments are a special case, count as a usage
    for (final partialAssignment
        in assignments.whereType<PartialSynthAssignment>()) {
      singleUseSignals.remove(partialAssignment.src);
    }

    final singleUsageInlineableSubmoduleInstantiations =
        inlineableSubmoduleInstantiations.where((subModuleInstantiation) {
      // inlineable modules have only 1 result signal
      final resultSynthLogic = subModuleInstantiation.inlineResultLogic!;

      return singleUseSignals.contains(resultSynthLogic);
    });

    // remove any inlineability for those that want no expressions
    for (final MapEntry(key: subModule, value: instantiation)
        in moduleToSubModuleInstantiationMap.entries) {
      if (subModule is SystemVerilog) {
        singleUseSignals.removeAll(subModule.expressionlessInputs.map((e) =>
            instantiation.inputMapping[e] ?? instantiation.inOutMapping[e]));
      }
      // ignore: deprecated_member_use_from_same_package
      else if (subModule is CustomSystemVerilog) {
        singleUseSignals.removeAll(subModule.expressionlessInputs.map((e) =>
            instantiation.inputMapping[e] ?? instantiation.inOutMapping[e]));
      }
    }

    final synthLogicToInlineableSynthSubmoduleMap =
        <SynthLogic, SystemVerilogSynthSubModuleInstantiation>{};
    for (final subModuleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      (subModuleInstantiation.module as InlineSystemVerilog).resultSignalName;

      // inlineable modules have only 1 result signal
      final resultSynthLogic = subModuleInstantiation.inlineResultLogic!;

      // clear declaration of intermediate signal replaced by inline
      internalSignals.remove(resultSynthLogic);

      // clear declaration of instantiation for inline module
      subModuleInstantiation.clearDeclaration();

      synthLogicToInlineableSynthSubmoduleMap[resultSynthLogic] =
          subModuleInstantiation;
    }

    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap =
          synthLogicToInlineableSynthSubmoduleMap;
    }
  }

  /// Finds all [InlineSystemVerilog] modules where all ports are [LogicNet]s
  /// and which have not had their declarations cleared and replaces them with a
  /// [_NetConnect] assignment instead of a normal assignment.
  void _replaceInOutConnectionInlineableModules() {
    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values.toList().where((e) =>
            e.module is InlineSystemVerilog &&
            e.needsDeclaration &&
            e.outputMapping.isEmpty &&
            e.inOutMapping.isNotEmpty)) {
      // algorithm:
      // - mark module as not needing declaration
      // - add a net_connect
      // - update the net_connect's inlineablesynthsubmodulemap

      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.clearDeclaration();

      final resultName = (subModuleInstantiation.module as InlineSystemVerilog)
          .resultSignalName;

      final subModResult = subModuleInstantiation.inOutMapping[resultName]!;

      // use a dummy as a placeholder, it will not really be used since we are
      // updating the inlineable map
      final dummy =
          SynthLogic(LogicNet(name: 'DUMMY', width: subModResult.width));

      final netConnectSynthSubmod = _addNetConnect(subModResult, dummy)
        ..synthLogicToInlineableSynthSubmoduleMap ??= {};

      netConnectSynthSubmod.synthLogicToInlineableSynthSubmoduleMap![dummy] =
          subModuleInstantiation;
    }
  }
}

/// A special [Module] for connecting or assigning two SystemVerilog nets
/// together bidirectionally.
///
/// The `alias` keyword in SystemVerilog could alternatively work, but many
/// tools do not support it, so this `module` definition is a convenient trick
/// to accomplish the same thing in a tool-compatible way.
class _NetConnect extends Module with SystemVerilog {
  static const String _definitionName = 'net_connect';

  /// The width of the nets on this instance.
  final int width;

  @override
  bool get hasBuilt =>
      // we force it to say it has built since it is being generated post-build
      true;

  /// The name of net 0.
  static final String n0Name = Naming.unpreferredName('n0');

  /// The name of net 1.
  static final String n1Name = Naming.unpreferredName('n1');

  _NetConnect(LogicNet n0, LogicNet n1)
      : assert(n0.width == n1.width, 'Widths must be equal.'),
        width = n0.width,
        super(
          definitionName: _definitionName,
          name: _definitionName,
        ) {
    n0 = addInOut(n0Name, n0, width: width);
    n1 = addInOut(n1Name, n1, width: width);
  }

  @override
  String instantiationVerilog(
      String instanceType, String instanceName, Map<String, String> ports) {
    assert(instanceType == _definitionName,
        'Instance type selected should match the definition name.');
    return '$instanceType'
        ' #(.WIDTH($width))'
        ' $instanceName'
        ' (${ports[n0Name]}, ${ports[n1Name]});';
  }

  @override
  String? definitionVerilog(String definitionType) => '''
// A special module for connecting two nets bidirectionally
module $definitionType #(parameter WIDTH=1) (w, w); 
inout wire[WIDTH-1:0] w;
endmodule''';
}
