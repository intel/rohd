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

    for (final subModuleInstantiation in subModuleInstantiations) {
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

    // Resolves a [SynthLogic] through any replacement that may have occurred
    // during earlier merging so that identity comparisons are consistent.
    SynthLogic resolve(SynthLogic synthLogic) =>
        synthLogic.replacement ?? synthLogic;

    // Arrays which are used as a whole (not just element-by-element) anywhere:
    // as a port of this module, in a submodule port mapping, or in an
    // assignment.  We must NOT inline away the elements of such arrays, since
    // the array declaration is still needed (and elements could lose
    // connections).
    final aggregateUsedArrays = <SynthLogic>{};
    void markIfAggregateArray(SynthLogic? synthLogic) {
      if (synthLogic != null && synthLogic.isArray) {
        aggregateUsedArrays.add(resolve(synthLogic));
      }
    }

    [...inputs, ...outputs, ...inOuts].forEach(markIfAggregateArray);
    for (final subModuleInstantiation in subModuleInstantiations) {
      [
        ...subModuleInstantiation.inputMapping.values,
        ...subModuleInstantiation.outputMapping.values,
        ...subModuleInstantiation.inOutMapping.values,
      ].forEach(markIfAggregateArray);
    }
    for (final assignment in assignments) {
      markIfAggregateArray(assignment.src);
      markIfAggregateArray(assignment.dst);
    }

    // Signals still referenced directly by an assignment must not be inlined
    // away.  This is especially important for array elements, whose assignments
    // are not collapsed away like mergeable signals.
    final assignmentReferencedSignals = <SynthLogic>{
      for (final assignment in assignments) ...[
        // don't need to [resolve] since assignment takes care of that
        assignment.src,
        assignment.dst,
      ]
    };

    // The set of [SynthLogic]s which are the (single) result of an inlineable
    // submodule that still needs instantiation (e.g. a 1-bit `BusSubset`).
    final inlineableResultLogics = <SynthLogic>{};
    for (final subModuleInstantiation in inlineableSubmoduleInstantiations) {
      final resultLogic = subModuleInstantiation.inlineResultLogic;
      if (resultLogic != null && subModuleInstantiation.needsInstantiation) {
        inlineableResultLogics.add(resolve(resultLogic));
      }
    }

    /// Whether [signal] is an array element produced by an inlineable submodule
    /// that could (subject to whole-array checks below) be safely inlined
    /// directly into its single consumer.
    bool isInlineableArrayElementCandidate(SynthLogic signal) =>
        signal is SynthLogicArrayElement &&
        // produced by an inlineable submodule (e.g. a 1-bit `BusSubset`)
        inlineableResultLogics.contains(resolve(signal)) &&
        // must be clearable (not a port of this module) so the element and,
        // once the whole array is consumed, the array declaration can be
        // dropped
        signal.isClearable &&
        // the parent array must not be used as a whole anywhere
        !aggregateUsedArrays.contains(resolve(signal.parentArray)) &&
        // the element must not still be referenced by an assignment
        !assignmentReferencedSignals.contains(resolve(signal));

    // individually-safe, single-use array-element results
    final candidateElements = <SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      if (signalUsageCount == 1 && isInlineableArrayElementCandidate(signal)) {
        candidateElements.add(resolve(signal));
      }
    });

    // Only inline array elements when the WHOLE parent array will be replaced,
    // i.e. every element of the array is itself an inlineable candidate.
    // Partial inlining is unsafe: the array would remain declared and its
    // remaining (e.g. undriven or differently-driven) elements could change
    // behavior (such as `x` vs `z` on undriven bits).
    final approvedElements = <SynthLogic>{};
    final candidatesByArray = <SynthLogic, Set<SynthLogic>>{};
    for (final element in candidateElements) {
      candidatesByArray
          .putIfAbsent(resolve((element as SynthLogicArrayElement).parentArray),
              () => {})
          .add(element);
    }
    candidatesByArray.forEach((parentArray, arrayCandidates) {
      final allElementSynthLogics = parentArray.logics
          .whereType<LogicArray>()
          .expand((logicArray) => logicArray.elements)
          .map(getSynthLogic)
          .nonNulls
          .map(resolve)
          .toSet();
      if (allElementSynthLogics.isNotEmpty &&
          allElementSynthLogics.every(candidateElements.contains)) {
        approvedElements.addAll(arrayCandidates);
      }
    });

    final singleUseSignals = <SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      // don't collapse if:
      //  - used more than once
      //  - inline modules for preferred names
      if (signalUsageCount == 1 &&
          (signal.mergeable || approvedElements.contains(resolve(signal)))) {
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

      return singleUseSignals.contains(resultSynthLogic) &&

          // don't inline modules if they were cleared from instantiation
          subModuleInstantiation.needsInstantiation;
    });

    // remove any inlineability for those that want no expressions
    for (final instantiation in subModuleInstantiations) {
      final subModule = instantiation.module;
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
    final inlinedParentArrays = <SynthLogic>{};
    for (final subModuleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      (subModuleInstantiation.module as InlineSystemVerilog).resultSignalName;

      // inlineable modules have only 1 result signal
      final resultSynthLogic = subModuleInstantiation.inlineResultLogic!;

      // clear declaration of intermediate signal replaced by inline
      internalSignals.remove(resultSynthLogic);

      // when inlining an array element, its declaration comes from the parent
      // array, so clear it explicitly and remember the parent array so we can
      // (potentially) drop the whole array if all its elements are inlined
      if (resultSynthLogic is SynthLogicArrayElement) {
        resultSynthLogic.clearDeclaration();
        inlinedParentArrays.add(resolve(resultSynthLogic.parentArray));
      }

      // clear declaration of instantiation for inline module
      subModuleInstantiation.clearInstantiation();

      synthLogicToInlineableSynthSubmoduleMap[resultSynthLogic] =
          subModuleInstantiation;
    }

    // Drop any parent array whose elements have all been inlined away, so the
    // now-unused array declaration is not emitted.
    for (final parentArray in inlinedParentArrays) {
      if (parentArray.declarationCleared ||
          !parentArray.isClearable ||
          parentArray.isPort(module) ||
          parentArray.isStructPortElement(module)) {
        continue;
      }

      final anyElementPresent = parentArray.logics.any((logic) =>
          (logic as LogicArray).elements.any(logicHasPresentSynthLogic));

      if (!anyElementPresent) {
        parentArray.clearDeclaration();
        internalSignals.remove(parentArray);
      }
    }

    for (final subModuleInstantiation in subModuleInstantiations) {
      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap =
          synthLogicToInlineableSynthSubmoduleMap;
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
            e.inOutMapping.isNotEmpty)) {
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
module $definitionType #(parameter int WIDTH=1) (w, w);
inout wire[WIDTH-1:0] w;
endmodule''';
}
