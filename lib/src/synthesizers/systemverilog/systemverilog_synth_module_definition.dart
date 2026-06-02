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

  /// A shared mapping from [SynthLogic]s which are the result of an inlineable
  /// submodule to the instantiation that produces them.
  ///
  /// Populated by both [_collapseAggregateConnections] and
  /// [_collapseChainableModules], then distributed to every submodule
  /// instantiation so that inline rendering (including recursive, multi-level
  /// chains) can resolve them.
  final Map<SynthLogic, SystemVerilogSynthSubModuleInstantiation>
      _inlineableSubmoduleMap = {};

  @override
  void process() {
    _collapseAggregateConnections();
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

  /// Collapses an internal aggregate signal (e.g. a [LogicArray]) whose
  /// individual elements are each connected one-to-one to some other signal,
  /// and which is itself used as a whole in exactly one place, by replacing
  /// that single aggregate use with an inlined concatenation ([Swizzle]) of the
  /// per-element sources.
  ///
  /// For example, a parent with individual nets `sig0..sigN` each connected to
  /// an element of an internal array `arr` that feeds a single child array
  /// port would otherwise emit one `net_connect` (or `assign`) per element plus
  /// a declaration of `arr`.  This collapses all of that into a single
  /// `.port({sigN, ..., sig0})` connection and drops `arr`.
  ///
  /// This works for both nets (bidirectional `inout` connections, where the
  /// concatenation is a legal net lvalue) and non-nets (a driven
  /// concatenation).
  void _collapseAggregateConnections() {
    // Resolves a [SynthLogic] through any merge replacement so identity
    // comparisons are consistent.
    SynthLogic resolve(SynthLogic synthLogic) =>
        synthLogic.replacement ?? synthLogic;

    // Loop until no further collapses occur: collapsing one aggregate can make
    // another eligible (e.g. chains of aggregates).  Each collapse strictly
    // removes work (clears an aggregate and its element assignments) and an
    // already-collapsed aggregate is no longer a candidate, so this terminates.
    var changed = true;
    while (changed) {
      changed = false;

      // Count how many times each array [SynthLogic] is used "as a whole",
      // along with where (a submodule port mapping is the only use we can
      // currently inline into).
      final aggregateUseCount = <SynthLogic, int>{};
      final aggregatePortUse = <SynthLogic,
          ({
        SystemVerilogSynthSubModuleInstantiation instantiation,
        String portName,
      })>{};

      void noteWholeUse(SynthLogic? synthLogic) {
        if (synthLogic != null && synthLogic.isArray) {
          final resolved = resolve(synthLogic);
          aggregateUseCount.update(resolved, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      for (final instantiation in subModuleInstantiations) {
        instantiation as SystemVerilogSynthSubModuleInstantiation;
        for (final entry in instantiation.inputMapping.entries) {
          noteWholeUse(entry.value);
          if (entry.value.isArray) {
            aggregatePortUse[resolve(entry.value)] =
                (instantiation: instantiation, portName: entry.key);
          }
        }
        for (final entry in instantiation.inOutMapping.entries) {
          noteWholeUse(entry.value);
          if (entry.value.isArray) {
            aggregatePortUse[resolve(entry.value)] =
                (instantiation: instantiation, portName: entry.key);
          }
        }
        // outputs of submodules can't be replaced by an inline concatenation
        instantiation.outputMapping.values.forEach(noteWholeUse);
      }

      // Assignments and this-module ports also count as whole-aggregate uses
      // (and we cannot inline into those today, so they just disqualify).
      [...inputs, ...outputs, ...inOuts].forEach(noteWholeUse);
      for (final assignment in assignments) {
        noteWholeUse(assignment.src);
        noteWholeUse(assignment.dst);
      }

      // Map from each array element to the assignment(s) connecting it, and a
      // count of every place each array element is used (submodule port
      // mappings and assignments).  An element is only safe to inline if its
      // sole appearance is its single connecting assignment; if it is read
      // anywhere else (e.g. by a reduction), the aggregate must stay intact.
      final elementAssignments = <SynthLogic, List<SynthAssignment>>{};
      final elementUseCount = <SynthLogic, int>{};
      void noteElementUse(SynthLogic? synthLogic) {
        if (synthLogic is SynthLogicArrayElement) {
          elementUseCount.update(resolve(synthLogic), (v) => v + 1,
              ifAbsent: () => 1);
        }
      }

      for (final instantiation in subModuleInstantiations) {
        instantiation as SystemVerilogSynthSubModuleInstantiation;
        instantiation.inputMapping.values.forEach(noteElementUse);
        instantiation.outputMapping.values.forEach(noteElementUse);
        instantiation.inOutMapping.values.forEach(noteElementUse);
      }
      for (final assignment in assignments) {
        noteElementUse(assignment.src);
        noteElementUse(assignment.dst);
        for (final end in [assignment.src, assignment.dst]) {
          if (end is SynthLogicArrayElement) {
            elementAssignments
                .putIfAbsent(resolve(end), () => [])
                .add(assignment);
          }
        }
      }

      for (final aggEntry in aggregatePortUse.entries) {
        final agg = aggEntry.key;
        final use = aggEntry.value;

        // Restriction: exactly one whole-aggregate use, which is the port use
        // we found.  This single-use restriction mirrors the other collapsing
        // mechanisms; it could be relaxed later (e.g. duplicating the
        // concatenation into multiple consumers).
        if ((aggregateUseCount[agg] ?? 0) != 1) {
          continue;
        }

        // The aggregate must be a clearable internal signal: mergeable (so its
        // name carries no meaning to preserve) and not a port.  This mirrors
        // the conservatism of the other collapsing mechanisms: renameable or
        // reserved aggregates are left intact so their declared names survive.
        if (agg.declarationCleared ||
            !agg.isClearable ||
            agg.isPort(module) ||
            !internalSignals.contains(agg)) {
          continue;
        }

        // The consuming port must accept expressions.
        final consumer = use.instantiation.module;
        if (consumer is SystemVerilog &&
            consumer.expressionlessInputs.contains(use.portName)) {
          continue;
        }

        // Gather each element's single source (the other end of its single
        // connecting assignment), in element order (index 0 = LSB).
        final elementLogics = agg.logics
            .whereType<LogicArray>()
            .first
            .elements
            .map(getSynthLogic)
            .map((e) => e == null ? null : resolve(e))
            .toList();

        final elementSources = <SynthLogic>[];
        var allElementsSingleSourced = true;
        for (final element in elementLogics) {
          if (element == null) {
            allElementsSingleSourced = false;
            break;
          }
          final connectingAssignments = elementAssignments[element];
          if (connectingAssignments == null ||
              connectingAssignments.length != 1) {
            allElementsSingleSourced = false;
            break;
          }
          // The element must not be used anywhere other than its single
          // connecting assignment (e.g. it must not also be read by a
          // reduction or feed another submodule); otherwise the aggregate's
          // declaration is still needed.
          if ((elementUseCount[element] ?? 0) != 1) {
            allElementsSingleSourced = false;
            break;
          }
          final assignment = connectingAssignments.single;
          final source =
              assignment.src == element ? assignment.dst : assignment.src;
          if (source == element) {
            allElementsSingleSourced = false;
            break;
          }
          elementSources.add(source);
        }

        if (!allElementsSingleSourced || elementSources.isEmpty) {
          continue;
        }

        // Net aggregates can only collapse if their sources are also nets (the
        // concatenation is a net lvalue), and non-net likewise.
        if (elementSources.any((e) => e.isNet != agg.isNet)) {
          continue;
        }

        // If every source is an element of one common parent array (in any
        // order), the aggregate is just a re-arrangement of an existing array
        // and there is nothing to consolidate; passing that array (or letting
        // the other collapsing mechanisms merge it) yields cleaner output, so
        // leave it alone.  The value of this optimization is consolidating
        // otherwise-separate signals into a single concatenation.
        if (elementSources.every((e) => e is SynthLogicArrayElement)) {
          final parents = elementSources
              .map((e) => resolve((e as SynthLogicArrayElement).parentArray))
              .toSet();
          if (parents.length == 1) {
            continue;
          }
        }

        // Fabricate a swizzle (post-build instrumentation, not connected to the
        // real hardware) whose concatenation reproduces the aggregate, and
        // register it so the single aggregate use renders as the inline
        // concatenation.
        _addSwizzleConnect(agg, elementSources);

        // Remove the now-inlined element assignments and clear the aggregate
        // declaration.
        final elementSet = elementLogics.nonNulls.toSet();
        assignments.removeWhere((assignment) =>
            elementSet.contains(resolve(assignment.src)) ||
            elementSet.contains(resolve(assignment.dst)));
        agg.clearDeclaration();
        internalSignals.remove(agg);

        changed = true;
      }
    }
  }

  /// Fabricates a [_SwizzleConnect] that represents [agg] as the inline
  /// concatenation of [elementSources] (ordered with index 0 as the LSB), and
  /// registers it in [_inlineableSubmoduleMap].
  void _addSwizzleConnect(SynthLogic agg, List<SynthLogic> elementSources) {
    final isNet = agg.isNet;

    // signals are MSB-first for the [Swizzle] (out = {signals[0], ...}).
    final sourcesInSignalOrder = elementSources.reversed.toList();
    final dummySignals = <Logic>[
      for (final source in sourcesInSignalOrder)
        isNet ? LogicNet(width: source.width) : Logic(width: source.width),
    ];

    final swizzle = _SwizzleConnect(dummySignals);

    final swizzleInst = getSynthSubModuleInstantiation(swizzle)
        as SystemVerilogSynthSubModuleInstantiation;

    // [orderedInputPortNames] are in creation order (`in0`, `in1`, ...), which
    // the [Swizzle] assigns to `signals.reversed`; i.e. `in0` is the LSB.  So
    // port `in${i}` corresponds to element `i` (LSB-first).
    for (var i = 0; i < elementSources.length; i++) {
      final portName = swizzle.orderedInputPortNames[i];
      final source = elementSources[i];
      if (isNet) {
        swizzleInst.setInOutMapping(portName, source);
      } else {
        swizzleInst.setInputMapping(portName, source);
      }
    }

    if (isNet) {
      swizzleInst.setInOutMapping(swizzle.resultSignalName, agg);
    } else {
      swizzleInst.setOutputMapping(swizzle.resultSignalName, agg);
    }

    swizzleInst.clearInstantiation();

    supportingModules.add(swizzle);

    _inlineableSubmoduleMap[agg] = swizzleInst;
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

    final synthLogicToInlineableSynthSubmoduleMap = _inlineableSubmoduleMap;
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
    // now-unused array declaration is not emitted.  This considers the whole
    // array hierarchy (collecting ancestors) so that, for multi-dimensional
    // arrays, a parent array whose sub-arrays were all dropped is itself
    // dropped.  A fixed-point loop is used since dropping one sub-array can
    // make its parent droppable regardless of visitation order.
    final candidateParentArrays = <SynthLogic>{};
    final ancestorsToCollect = [...inlinedParentArrays];
    while (ancestorsToCollect.isNotEmpty) {
      final parentArray = resolve(ancestorsToCollect.removeLast());
      if (candidateParentArrays.add(parentArray) &&
          parentArray is SynthLogicArrayElement) {
        ancestorsToCollect.add(parentArray.parentArray);
      }
    }

    bool elementsAllAbsent(SynthLogic parentArray) =>
        parentArray.logics.every((logic) =>
            !(logic as LogicArray).elements.any(logicHasPresentSynthLogic));

    var droppedAny = true;
    while (droppedAny) {
      droppedAny = false;
      for (final parentArray in candidateParentArrays) {
        if (parentArray.declarationCleared ||
            !parentArray.isClearable ||
            parentArray.isPort(module) ||
            parentArray.isStructPortElement(module)) {
          continue;
        }

        if (elementsAllAbsent(parentArray)) {
          parentArray.clearDeclaration();
          internalSignals.remove(parentArray);
          droppedAny = true;
        }
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

/// A [Swizzle] fabricated post-build purely as instrumentation for
/// SystemVerilog generation; it is never connected to the real hardware
/// hierarchy or used in simulation.
///
/// Used by
/// [SystemVerilogSynthModuleDefinition._collapseAggregateConnections] to
/// render an aggregate's single use as an inline concatenation of its
/// per-element sources.
class _SwizzleConnect extends Swizzle {
  /// The names of the input ports, in the same order as the `signals` passed to
  /// the constructor.
  late final List<String> orderedInputPortNames;

  @override
  // forced since it is generated post-build
  bool get hasBuilt => true;

  _SwizzleConnect(super.signals) {
    orderedInputPortNames = (isNet ? inOuts.keys : inputs.keys)
        .where((name) => name != resultSignalName)
        .toList();
  }

  /// Whether this swizzle is for [LogicNet]s.
  bool get isNet => inOuts.isNotEmpty;
}
