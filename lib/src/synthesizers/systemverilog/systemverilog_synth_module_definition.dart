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
    _buildNetConnectsForNaming(pickName: true);
    _collapseMarkedChainableModules();
    _replaceInOutConnectionInlineableModules();
  }

  @override
  SynthSubModuleInstantiation createSubModuleInstantiation(Module m) =>
      SystemVerilogSynthSubModuleInstantiation(m);

  /// Creates a new [_NetConnect] module to synthesize assignment between two
  /// [LogicNet]s.
  SystemVerilogSynthSubModuleInstantiation _addNetConnect(
    SynthLogic dst,
    SynthLogic src, {
    bool pickName = false,
  }) {
    // make an (unconnected) module representing the assignment
    final netConnect = _NetConnect(
      LogicNet(width: dst.width),
      LogicNet(width: src.width),
    );

    // instantiate the module within the definition
    final netConnectSynthSubModInst =
        (getSynthSubModuleInstantiation(netConnect)
            as SystemVerilogSynthSubModuleInstantiation)
          // map inouts to the appropriate `_SynthLogic`s
          ..setInOutMapping(_NetConnect.n0Name, dst)
          ..setInOutMapping(_NetConnect.n1Name, src);

    // notify the `SynthBuilder` that it needs declaration
    supportingModules.add(netConnect);

    if (pickName) {
      netConnectSynthSubModInst.pickName(module);
    }

    return netConnectSynthSubModInst;
  }

  /// Builds [_NetConnect] instances for [LogicNet] assignments.
  void _buildNetConnectsForNaming({bool pickName = false}) {
    final reducedAssignments = <SynthAssignment>[];

    for (final assignment in assignments) {
      if (assignment.src.isNet && assignment.dst.isNet) {
        assert(
          assignment is! PartialSynthAssignment,
          'Net connections should not be partial assignments.',
        );

        _addNetConnect(assignment.dst, assignment.src, pickName: pickName);
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

  /// Collapses chainable, inlineable modules after naming.
  void _collapseMarkedChainableModules() {
    // collapse multiple lines of in-line assignments into one where they are
    // unnamed one-liners
    //  for example, be capable of creating lines like:
    //      assign x = a & b & c & _d_and_e
    //      assign _d_and_e = d & e
    //      assign y = _d_and_e

    final synthLogicToInlineableSynthSubmoduleMap =
        <SynthLogic, SystemVerilogSynthSubModuleInstantiation>{};
    for (final subModuleInstantiation in chainableModulesToCollapse
        .cast<SystemVerilogSynthSubModuleInstantiation>()) {
      // inlineable modules have only 1 result signal
      final resultSynthLogic = subModuleInstantiation.inlineResultLogic!;

      // clear declaration of intermediate signal replaced by inline
      internalSignals.remove(resultSynthLogic);

      // clear declaration of instantiation for inline module
      subModuleInstantiation.clearInstantiation();

      synthLogicToInlineableSynthSubmoduleMap[resultSynthLogic] =
          subModuleInstantiation;
    }

    for (final subModuleInstantiation in subModuleInstantiations) {
      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap = {
        ...?subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap,
        ...synthLogicToInlineableSynthSubmoduleMap,
      };
    }
  }

  /// Finds all [InlineSystemVerilog] modules where all ports are [LogicNet]s
  /// and which have not had their declarations cleared and replaces them with a
  /// [_NetConnect] assignment instead of a normal assignment.
  void _replaceInOutConnectionInlineableModules() {
    for (final subModuleInstantiation in subModuleInstantiations.toList().where(
          (e) =>
              e.module is InlineSystemVerilog &&
              e.needsInstantiation &&
              e.outputMapping.isEmpty &&
              e.inOutMapping.isNotEmpty,
        )) {
      // algorithm:
      // - mark module as not needing declaration
      // - add a net_connect
      // - update the net_connect's inlineablesynthsubmodulemap

      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.clearInstantiation();

      final resultName = (subModuleInstantiation.module as InlineSystemVerilog)
          .resultSignalName;

      final subModResult = subModuleInstantiation.inOutMapping[resultName]!;

      // use a dummy as a placeholder, it will not really be used since we are
      // updating the inlineable map
      final dummy = SynthLogic(
        LogicNet(name: 'DUMMY', width: subModResult.width),
        parentSynthModuleDefinition: this,
      );

      final netConnectSynthSubmod = _addNetConnect(
        subModResult,
        dummy,
        pickName: true,
      )..synthLogicToInlineableSynthSubmoduleMap ??= {};

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
        super(definitionName: _definitionName, name: _definitionName) {
    n0 = addInOut(n0Name, n0, width: width);
    n1 = addInOut(n1Name, n1, width: width);
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    assert(
      instanceType == _definitionName,
      'Instance type selected should match the definition name.',
    );
    return '$instanceType'
        ' #(.WIDTH($width))'
        ' $instanceName'
        ' (${ports[n0Name]}, ${ports[n1Name]});';
  }

  @override
  String? definitionVerilog(String definitionType) => '''
// A special module for connecting two nets bidirectionally
module $definitionType #(parameter int WIDTH=1) (w, w);
inout wire[WIDTH-1:0] w;
endmodule''';
}
