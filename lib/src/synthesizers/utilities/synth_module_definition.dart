// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_module_definition.dart
// Definitions for a module definition
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/namer.dart';

/// A version of [BusSubset] that can be used for slicing on [LogicStructure]
/// ports.
class _BusSubsetForStructSlice extends BusSubset {
  /// The stable destination [Logic] this slice drives.
  ///
  /// Used as the [instanceNameKey] so that, although a fresh
  /// [_BusSubsetForStructSlice] is created on every synthesis pass, its
  /// canonical instance name is memoized against the persistent destination
  /// signal and therefore does not drift run-to-run.
  final Logic _destination;

  /// Creates a [BusSubset] for use in [SynthModuleDefinition]s during
  /// [LogicStructure] port slicing.
  _BusSubsetForStructSlice(
    super.bus,
    super.startIndex,
    super.endIndex, {
    required Logic destination,
  })  : _destination = destination,
        super(name: 'struct_slice');

  // we override this since it's added post-build
  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => _destination;
}

/// A packed range of a base [SynthLogic], inclusive of [lower] and [upper].
class _SynthRangeRef {
  /// The signal whose packed range is referenced.
  final SynthLogic base;

  /// The lower index of the range.
  final int lower;

  /// The upper index of the range.
  final int upper;

  /// The number of bits in this range.
  int get width => upper - lower + 1;

  /// Creates a range reference.
  const _SynthRangeRef(this.base, this.lower, this.upper)
      : assert(lower >= 0, 'Invalid lower index'),
        assert(upper >= lower, 'Invalid upper index');

  /// Whether [other] is fully contained in this range.
  bool contains(_SynthRangeRef other) =>
      base == other.base && other.lower >= lower && other.upper <= upper;
}

/// Represents the definition of a module.
@internal
class SynthModuleDefinition {
  /// The [Module] being defined.
  final Module module;

  /// All the assignments that are part of this definition.
  final List<SynthAssignment> assignments = [];

  /// All other internal signals that are not ports.
  ///
  /// This is the only collection that may have mergeable items in it.
  final Set<SynthLogic> internalSignals = {};

  /// All the input ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<SynthLogic> inputs = {};

  /// All the output ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<SynthLogic> outputs = {};

  /// All the output ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<SynthLogic> inOuts = {};

  /// A mapping from original [Logic]s to the [SynthLogic]s that represent
  /// them.
  final Map<Logic, SynthLogic> logicToSynthMap = HashMap();

  /// A mapping from the original [Module]s to the
  /// [SynthSubModuleInstantiation]s that represent them.
  final Map<Module, SynthSubModuleInstantiation>
      moduleToSubModuleInstantiationMap = {};

  /// All the sub-module instantiations used within this definition which are
  /// still present (not removed).
  Iterable<SynthSubModuleInstantiation> get subModuleInstantiations =>
      moduleToSubModuleInstantiationMap.values;

  /// Chainable inline modules that should claim names after emitted objects.
  @protected
  final Set<SynthSubModuleInstantiation> chainableModulesToCollapse = {};

  // Weak-name marks do not remove objects from naming. They make likely
  // collapsed objects claim names after unmarked objects, so in a collision
  // the unmarked object keeps the basename and the marked object gets a suffix.
  final Set<SynthSubModuleInstantiation> _weakNameClaimSubmodules = {};

  final Set<SynthLogic> _weakNameClaimSignals = {};

  /// Indicates that [m] is a submodule used within this definition.
  ///
  /// This is only valid to call after all the submodules have been detected.
  /// This also updates as modules are pruned or removed during processing.
  @internal
  bool isSubmoduleAndPresent(Module? m) =>
      m != null &&
      moduleToSubModuleInstantiationMap.containsKey(m) &&
      moduleToSubModuleInstantiationMap[m]!.needsInstantiation;

  /// Either accesses a previously created [SynthSubModuleInstantiation]
  /// corresponding to [m], or else creates a new one and adds it to the
  /// [moduleToSubModuleInstantiationMap].
  SynthSubModuleInstantiation getSynthSubModuleInstantiation(Module m) {
    if (moduleToSubModuleInstantiationMap.containsKey(m)) {
      return moduleToSubModuleInstantiationMap[m]!;
    } else {
      final newSSMI = createSubModuleInstantiation(m);
      moduleToSubModuleInstantiationMap[m] = newSSMI;
      return newSSMI;
    }
  }

  /// Creates a [SynthSubModuleInstantiation] representing the instantiation of
  /// [m].
  ///
  /// This can be overridden to provide custom types for sub-module
  /// instantiation.
  @visibleForOverriding
  SynthSubModuleInstantiation createSubModuleInstantiation(Module m) =>
      SynthSubModuleInstantiation(m);

  @override
  String toString() => "module name: '${module.name}'";

  /// Indicates whether [logic] has a corresponding present [SynthLogic] in
  /// this definition.
  @internal
  bool logicHasPresentSynthLogic(Logic logic) {
    final synthLogic = logicToSynthMap[logic];
    if (synthLogic == null) {
      return false;
    } else if (synthLogic.declarationCleared) {
      return false;
    } else if (synthLogic.isStructPortElement()) {
      return true;
    } else {
      return true;
    }
  }

  /// Either accesses a previously created [SynthLogic] corresponding to
  /// [logic], or else creates a new one and adds it to the [logicToSynthMap].
  SynthLogic? getSynthLogic(Logic? logic) {
    if (logic == null) {
      return null;
    } else if (!(logic.parentModule == module ||
        (logic.isPort && logic.parentModule?.parent == module) ||
        logic is Const)) {
      // this is a signal not in this module or its submodules ports, so don't
      // add it as a SynthLogic in here!
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      SynthLogic newSynth;
      if (logic.isArrayMember) {
        // grab the parent array (potentially recursively)
        final parentArraySynthLogic =
            // ignore: unnecessary_null_checks
            getSynthLogic(logic.parentStructure!)!;

        // if there's already a parent whose element has a SynthLogic, reuse it
        final existingElementWithSynthLogic = parentArraySynthLogic.logics
            .map((e) => e.elements[logic.arrayIndex!])
            .firstWhereOrNull(logicToSynthMap.containsKey);
        if (existingElementWithSynthLogic != null) {
          final existingSynthLogic =
              logicToSynthMap[existingElementWithSynthLogic]!;
          logicToSynthMap[logic] = existingSynthLogic;
          return existingSynthLogic;
        }

        newSynth = SynthLogicArrayElement(
          logic,
          parentSynthModuleDefinition: this,
        );
      } else {
        final disallowConstName = (logic.isInput || logic.isInOut) &&
            // ignore: deprecated_member_use_from_same_package
            ((logic.parentModule is CustomSystemVerilog &&
                    // ignore: deprecated_member_use_from_same_package
                    (logic.parentModule! as CustomSystemVerilog)
                        .expressionlessInputs
                        .contains(logic.name)) ||
                (logic.parentModule is SystemVerilog &&
                    (logic.parentModule! as SystemVerilog)
                        .expressionlessInputs
                        .contains(logic.name)));

        final Naming? namingOverride;
        if (logic.isPort) {
          if (logic.parentModule != module) {
            // this is a submodule port, so it doesn't need to reserve the name
            namingOverride = Naming.mergeable;
          } else if (logic.parentStructure == null) {
            // this is not a sub-element of an array or structure
            namingOverride = Naming.reserved;
          } else if (logic.parentStructure != null &&
              logic.parentModule == module &&
              (logic.parentStructure!.parentModule != module ||
                  !logic.parentStructure!.isPort)) {
            // this is a port of this module which is a sub-element of a
            // structure that is not a port of this module
            namingOverride = Naming.reserved;
          } else {
            // this might be some sub-element that doesn't need a reserved port
            // name
            namingOverride = null;
          }
        } else {
          // non-port, don't override the name
          namingOverride = null;
        }

        newSynth = SynthLogic(
          logic,
          parentSynthModuleDefinition: this,
          namingOverride: namingOverride,
          constNameDisallowed: disallowConstName,
        );
      }

      logicToSynthMap[logic] = newSynth;

      if (logic is LogicArray) {
        // if we are an array, make sure we go down the stack of elements too
        logic.elements.forEach(getSynthLogic);
      }

      return newSynth;
    }
  }

  /// A [List] of supporting modules that need to be instantiated within this
  /// definition.
  final List<Module> supportingModules = [];

  /// Takes all the leaf elements of [port] and drives [port] with them, each
  /// with a partial assignment.
  ///
  /// This is intended for use when driving an output of a module from within
  /// the module, or for driving the input of a sub-module.
  @protected
  void _partialAssignStructPort(LogicStructure port) {
    assert(port is! LogicArray, 'Should only be used on non-array structs');

    final portSynth = getSynthLogic(port)!;

    var idx = 0;
    for (final leafElement in port.leafElements) {
      final leafSynth = getSynthLogic(leafElement)!;
      internalSignals.add(leafSynth);
      assignments.add(
        PartialSynthAssignment(
          leafSynth,
          portSynth,
          dstUpperIndex: idx + leafElement.width - 1,
          dstLowerIndex: idx,
        ),
      );
      idx += leafElement.width;
    }
  }

  /// Drives all leaf elements of [port] using a (modified) [BusSubset].
  ///
  /// This is intended for use when receiving from an input of a module from
  /// within the module, or for receiving the output of a sub-module.
  @protected
  void _subsetReceiveStructPort(LogicStructure port) {
    final portSynth = getSynthLogic(port)!;

    var idx = 0;
    for (final leafElement in port.leafElements) {
      final leafSynth = getSynthLogic(leafElement)!;
      internalSignals.add(leafSynth);

      // this is DISCONNECTED, just a module used for synthesizing
      final subsetMod = _BusSubsetForStructSlice(
        (port.isNet ? LogicNet.new : Logic.new)(
          width: port.width,
          name: 'DUMMY',
        ),
        idx,
        idx + leafElement.width - 1,
        destination: leafElement,
      );

      final ssmi = getSynthSubModuleInstantiation(subsetMod);

      if (port.isNet) {
        ssmi
          ..setInOutMapping(subsetMod.subset.name, leafSynth)
          ..setInOutMapping(subsetMod.original.name, portSynth);
      } else {
        ssmi
          ..setOutputMapping(subsetMod.subset.name, leafSynth)
          ..setInputMapping(subsetMod.original.name, portSynth);
      }

      idx += leafElement.width;
    }
  }

  /// Creates a new definition representation for this [module].
  SynthModuleDefinition(this.module)
      : assert(
            !(module is SystemVerilog &&
                module.generatedDefinitionType ==
                    DefinitionGenerationType.none),
            'Do not build a definition for a module'
            ' which generates no definition!') {
    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values)
      ..addAll(module.inOuts.values);

    for (final output in module.outputs.values) {
      final outputSynth = getSynthLogic(output)!;
      outputs.add(outputSynth);

      if (output is LogicStructure && output is! LogicArray) {
        _partialAssignStructPort(output);
      }
    }

    // make sure disconnected inputs are included
    for (final input in module.inputs.values) {
      final inputSynth = getSynthLogic(input)!;
      inputs.add(inputSynth);

      if (input is LogicStructure && input is! LogicArray) {
        _subsetReceiveStructPort(input);
      }
    }

    // make sure disconnected inouts are included, also
    for (final inOut in module.inOuts.values) {
      inOuts.add(getSynthLogic(inOut)!);

      if (inOut is LogicStructure && inOut is! LogicArray) {
        // for nets, we can just use the normal bus subset here in either
        // direction!
        _subsetReceiveStructPort(inOut);
      }
    }

    // find any named signals sitting around that don't do anything
    // this is not necessary for functionality, just nice naming inclusion
    logicsToTraverse.addAll(
      module.internalSignals.where(
        (element) => element.naming != Naming.unnamed,
      ),
    );

    // make sure floating modules are included
    for (final subModule in module.subModules) {
      getSynthSubModuleInstantiation(subModule);
      logicsToTraverse
        ..addAll(subModule.inputs.values)
        ..addAll(subModule.outputs.values)
        ..addAll(subModule.inOuts.values);

      subModule.inputs.values
          .whereType<LogicStructure>()
          .where((e) => e is! LogicArray)
          .forEach(_partialAssignStructPort);

      subModule.outputs.values
          .whereType<LogicStructure>()
          .where((e) => e is! LogicArray)
          .forEach(_subsetReceiveStructPort);

      subModule.inOuts.values
          .whereType<LogicStructure>()
          .where((e) => e is! LogicArray)
          .forEach(_subsetReceiveStructPort);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      final receiver = logicsToTraverse[i];

      assert(
        receiver.parentModule != null,
        'Any signal traced by this should have been detected by build,'
        ' but $receiver was not.',
      );

      if (receiver.parentModule != module &&
          !module.subModules.contains(receiver.parentModule)) {
        // This should never happen!
        assert(false, 'Receiver is not in this module or a submodule.');
        continue;
      }

      if (receiver is LogicStructure) {
        logicsToTraverse.addAll(receiver.elements);
      }

      if (receiver.isArrayMember) {
        // don't need to step up to any structure, just arrays
        logicsToTraverse.add(receiver.parentStructure!);
      }

      final synthReceiver = getSynthLogic(receiver)!;

      if (receiver is LogicNet) {
        // only for the leaves, that's why only `LogicNet` and not array/struct

        logicsToTraverse.addAll(
          [
            ...receiver.srcConnections,
            ...receiver.dstConnections,
          ].where((element) => element.parentModule == module),
        );

        for (final srcConnection in receiver.srcConnections) {
          if (srcConnection.parentModule == module ||
              (srcConnection.isOutput &&
                  srcConnection.parentModule!.parent == module)) {
            final netSynthDriver = getSynthLogic(srcConnection)!;

            assignments.add(SynthAssignment(netSynthDriver, synthReceiver));
          }
        }
      }

      final driver = receiver.srcConnection;

      final receiverIsConstant = driver == null && receiver is Const;

      final receiverParentStructureIsPort =
          receiver.parentStructure != null && receiver.parentStructure!.isPort;

      final receiverIsModuleInput =
          module.isInput(receiver) && !receiverParentStructureIsPort;
      final receiverIsModuleOutput =
          module.isOutput(receiver) && !receiverParentStructureIsPort;
      final receiverIsModuleInOut =
          module.isInOut(receiver) && !receiverParentStructureIsPort;

      final synthDriver = getSynthLogic(driver);

      if (receiverIsModuleInput) {
        inputs.add(synthReceiver);
      } else if (receiverIsModuleOutput) {
        outputs.add(synthReceiver);
      } else if (receiverIsModuleInOut) {
        inOuts.add(synthReceiver);
      } else {
        assert(
          !inputs.contains(synthReceiver) &&
              !outputs.contains(synthReceiver) &&
              !inOuts.contains(synthReceiver),
          'Internal signals should not be ports also.',
        );
        internalSignals.add(synthReceiver);
      }

      final receiverIsSubmoduleInOut =
          receiver.isInOut && (receiver.parentModule?.parent == module);
      if (receiverIsSubmoduleInOut) {
        final subModule = receiver.parentModule!;

        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement()) {
          getSynthSubModuleInstantiation(
            subModule,
          ).setInOutMapping(receiver.name, synthReceiver);
        }

        logicsToTraverse.addAll(subModule.inOuts.values);
      }

      final receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);

      if (receiverIsSubModuleOutput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement()) {
          getSynthSubModuleInstantiation(
            subModule,
          ).setOutputMapping(receiver.name, synthReceiver);
        }

        logicsToTraverse
          ..addAll(subModule.inputs.values)
          ..addAll(subModule.inOuts.values);
      } else if (driver != null) {
        if (!module.isInput(receiver) && !module.isInOut(receiver)) {
          // stop at the input to this module
          logicsToTraverse.add(driver);
          assignments.add(SynthAssignment(synthDriver!, synthReceiver));
        }
      } else if (receiverIsConstant && !receiver.value.isFloating) {
        // this is a const that is valid, *partially* invalid (e.g. 0b1z1x0),
        // or anything that's not *entirely* floating (since those we can leave
        // as completely undriven).

        // make a new const node, it will merge away if not needed
        final newReceiverConst = getSynthLogic(Const(receiver.value))!;
        internalSignals.add(newReceiverConst);
        assignments.add(SynthAssignment(newReceiverConst, synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement()) {
          getSynthSubModuleInstantiation(
            subModule,
          ).setInputMapping(receiver.name, synthReceiver);
        }
      }
    }

    // The order of these is important!
    _collapseArrays();
    _collapseSimpleRangeAssignments();
    _collapseWideArrayElementRangeSources();
    _collapseChainedRangeAssignments();
    _collapseGeneratedSubsetSwizzleRangeAssignments();
    _collapseAssignments();
    _assignSubmodulePortMapping();

    _pruneUnused();

    // Naming has two base-owned phases: mark likely-collapsed objects as weak
    // name claimants, then pick names. After that, synthesizers may
    // process/collapse the marked objects.
    _prepareForNaming();
    _pickNames();
    process();
  }

  /// Performs base-owned preparation before names are picked.
  ///
  /// Synthesizers must not override this method.
  void _prepareForNaming() {
    _markPotentiallyCollapsedObjectsForNaming();
  }

  /// Marks objects likely to be collapsed by some synthesizers as weak name
  /// claimants.
  ///
  /// Marked objects are still named. They just claim names after unmarked
  /// objects, biasing collision resolution so unmarked objects keep basenames
  /// and marked objects receive suffixes like `_1` or `_2`.
  void _markPotentiallyCollapsedObjectsForNaming() {
    chainableModulesToCollapse
      ..clear()
      ..addAll(_findChainableModulesToCollapse());
    _weakNameClaimSubmodules.clear();
    _weakNameClaimSignals.clear();

    for (final subModuleInstantiation in chainableModulesToCollapse) {
      _weakNameClaimSubmodules.add(subModuleInstantiation);
      final resultLogic = _inlineResultLogic(subModuleInstantiation);
      if (resultLogic != null) {
        _weakNameClaimSignals.add(resultLogic);
        if (resultLogic is SynthLogicArrayElement) {
          _weakNameClaimSignals.add(resultLogic.parentArray.resolved);
        }
      }
    }
  }

  /// Finds chainable, inlineable modules.
  Iterable<SynthSubModuleInstantiation> _findChainableModulesToCollapse() {
    final inlineableSubmoduleInstantiations = subModuleInstantiations.where(
      (submoduleInstantiation) =>
          submoduleInstantiation.module is InlineSystemVerilog,
    );

    final signalUsage = <SynthLogic, int>{};

    for (final subModuleInstantiation in subModuleInstantiations) {
      for (final inSynthLogic in [
        ...subModuleInstantiation.inputMapping.values,
        ...subModuleInstantiation.inOutMapping.values,
      ]) {
        if (inputs.contains(inSynthLogic) || inOuts.contains(inSynthLogic)) {
          continue;
        }

        if (_inlineResultLogic(subModuleInstantiation) == inSynthLogic) {
          continue;
        }

        signalUsage.update(
          inSynthLogic,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    // Arrays which are used as a whole (not just element-by-element) anywhere:
    // as a port of this module, in a submodule port mapping, or in an
    // assignment.  We must not inline away elements of such arrays, since the
    // array declaration is still needed and elements could lose connections.
    final aggregateUsedArrays = <SynthLogic>{};
    void markIfAggregateArray(SynthLogic? synthLogic) {
      if (synthLogic != null && synthLogic.isArray) {
        aggregateUsedArrays.add(synthLogic.resolved);
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
    // away. This is especially important for array elements, whose assignments
    // are not collapsed away like mergeable signals.
    final assignmentReferencedSignals = <SynthLogic>{
      for (final assignment in assignments) ...[
        assignment.src,
        assignment.dst,
      ],
    };

    final inlineableResultLogics = <SynthLogic>{};
    for (final subModuleInstantiation in inlineableSubmoduleInstantiations) {
      final resultLogic = _inlineResultLogic(subModuleInstantiation);
      if (resultLogic != null && subModuleInstantiation.needsInstantiation) {
        inlineableResultLogics.add(resultLogic.resolved);
      }
    }

    bool isInlineableArrayElementCandidate(SynthLogic signal) =>
        signal is SynthLogicArrayElement &&
        inlineableResultLogics.contains(signal.resolved) &&
        signal.isClearable &&
        !aggregateUsedArrays.contains(signal.parentArray.resolved) &&
        !assignmentReferencedSignals.contains(signal.resolved);

    final candidateElements = <SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      if (signalUsageCount == 1 && isInlineableArrayElementCandidate(signal)) {
        candidateElements.add(signal.resolved);
      }
    });

    // Only inline array elements when the whole parent array will be replaced.
    // Partial inlining is unsafe: the array would remain declared and its
    // remaining elements could change behavior (for example `x` vs `z` on
    // undriven bits).
    final approvedElements = <SynthLogic>{};
    final candidatesByArray = <SynthLogic, Set<SynthLogic>>{};
    for (final element in candidateElements) {
      candidatesByArray
          .putIfAbsent(
            (element as SynthLogicArrayElement).parentArray.resolved,
            () => {},
          )
          .add(element);
    }
    candidatesByArray.forEach((parentArray, arrayCandidates) {
      final allElementSynthLogics = parentArray.logics
          .whereType<LogicArray>()
          .expand((logicArray) => logicArray.elements)
          .map(getSynthLogic)
          .nonNulls
          .map((e) => e.resolved)
          .toSet();
      if (allElementSynthLogics.isNotEmpty &&
          allElementSynthLogics.every(candidateElements.contains)) {
        approvedElements.addAll(arrayCandidates);
      }
    });

    final singleUseSignals = <SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      if (signalUsageCount == 1 &&
          (signal.mergeable || approvedElements.contains(signal.resolved))) {
        singleUseSignals.add(signal);
      }
    });

    for (final partialAssignment
        in assignments.whereType<PartialSynthAssignment>()) {
      singleUseSignals.remove(partialAssignment.src);
    }

    for (final instantiation in subModuleInstantiations) {
      final subModule = instantiation.module;
      if (subModule is SystemVerilog) {
        singleUseSignals.removeAll(
          subModule.expressionlessInputs.map(
            (e) =>
                instantiation.inputMapping[e] ?? instantiation.inOutMapping[e],
          ),
        );
        // ignore: deprecated_member_use_from_same_package
      } else if (subModule is CustomSystemVerilog) {
        singleUseSignals.removeAll(
          subModule.expressionlessInputs.map(
            (e) =>
                instantiation.inputMapping[e] ?? instantiation.inOutMapping[e],
          ),
        );
      }
    }

    return inlineableSubmoduleInstantiations.where((subModuleInstantiation) {
      final resultSynthLogic = _inlineResultLogic(subModuleInstantiation);

      return resultSynthLogic != null &&
          singleUseSignals.contains(resultSynthLogic) &&
          subModuleInstantiation.needsInstantiation;
    });
  }

  SynthLogic? _inlineResultLogic(SynthSubModuleInstantiation instantiation) {
    final subModule = instantiation.module;
    if (subModule is! InlineSystemVerilog) {
      return null;
    }

    return instantiation.outputMapping[subModule.resultSignalName] ??
        instantiation.inOutMapping[subModule.resultSignalName];
  }

  /// Performs additional processing on the current definition to simplify,
  /// reduce, etc.
  @protected
  @visibleForOverriding
  void process() {
    // by default, nothing!
  }

  /// Prunes any signals that are not used in this definition, including any
  /// swizzles/subsets/etc., iteratively until there's nothing left to prune.
  ///
  /// Note that this can remove signals from [internalSignals] after marking
  /// them as having their declaration cleared.
  void _pruneUnused() {
    var changed = true;

    while (changed) {
      changed = false;

      // (roughly) conditions for allowing a signal to be removed:
      // - modules that are removable: BusSubset, Swizzle
      //   - if none of the ports are connected to any signals that exist
      // - signals that are removable; all of:
      //   - `clearable`, structs/arrays all elements are cleared
      //   - no drivers or receivers (ignore ports of removed modules)
      //   - not a port of the current module
      // - assignments that are removable:
      //   - the driver has no driver OR the receiver has no receivers

      final reducedInternalSignals = <SynthLogic>[];
      for (final internalSignal in internalSignals) {
        // if it's cleared already, just skip it
        if (internalSignal.declarationCleared) {
          changed = true;
          continue;
        }

        // if it's not a clearable signal (for whatever reason), can't remove it
        if (!internalSignal.isClearable) {
          reducedInternalSignals.add(internalSignal);
          continue;
        }

        if (internalSignal.isStructPortElement(module)) {
          // can't remove elements of struct ports of this module
          reducedInternalSignals.add(internalSignal);
          continue;
        }

        if (internalSignal.isPort(module)) {
          // can't remove ports of this module
          reducedInternalSignals.add(internalSignal);
          continue;
        }

        final logics = internalSignal.logics;

        if (internalSignal.isArray) {
          if (logics.any(
            (logicArray) => logicArray.elements.any(logicHasPresentSynthLogic),
          )) {
            // if it's an array, can only remove if all elements are removed
            reducedInternalSignals.add(internalSignal);
          } else {
            // if it's an array and all elements are gone, we can remove it
            internalSignal.clearDeclaration();
            changed = true;
          }

          continue;
        }

        final isCustomSvModPort = logics.any(
          (logic) =>
              logic.isPort &&
              isSubmoduleAndPresent(logic.parentModule) &&
              ((logic.parentModule! is SystemVerilog &&
                      !(logic.parentModule! as SystemVerilog)
                          .acceptsEmptyPortConnections) ||
                  // ignore: deprecated_member_use_from_same_package
                  logic.parentModule! is CustomSystemVerilog),
        );

        if (!isCustomSvModPort) {
          if (internalSignal.isNet) {
            final anyInternalConnections = [
              ...internalSignal.srcConnections,
              ...internalSignal.dstConnections,
            ]
                .where(
                  (e) =>
                      (e.parentModule == module ||
                          ( // in case of sub-module output driving a net
                              e.parentModule?.parent == module &&
                                  e.isOutput)) &&
                      logicHasPresentSynthLogic(e),
                )
                .isNotEmpty;

            if (anyInternalConnections) {
              reducedInternalSignals.add(internalSignal);
              continue;
            }

            final connectedSubModules = logics
                .map((e) => e.parentModule)
                .nonNulls
                .where(
                  (e) =>
                      e != module &&
                      getSynthSubModuleInstantiation(e).needsInstantiation,
                )
                .toSet();

            if (connectedSubModules.length > 1) {
              reducedInternalSignals.add(internalSignal);
              continue;
            }

            // If the signal appears in multiple inout port mappings on the
            // same (single) connected submodule, it's a loopback and needs
            // a wire declaration so both ports can reference it by name.
            final hasInOutLoopback = connectedSubModules.any(
              (m) =>
                  getSynthSubModuleInstantiation(m)
                      .inOutMapping
                      .values
                      .where((v) => v == internalSignal)
                      .length >
                  1,
            );

            if (hasInOutLoopback) {
              reducedInternalSignals.add(internalSignal);
              continue;
            }

            // otherwise, we can remove this net
            internalSignal.clearDeclaration();
            changed = true;
            continue;
          }

          if (!internalSignal.hasSrcConnectionsPresent()) {
            internalSignal.clearDeclaration();
            changed = true;
            continue;
          }

          if (!internalSignal.hasDstConnectionsPresent()) {
            internalSignal.clearDeclaration();
            changed = true;
            continue;
          }
        }

        reducedInternalSignals.add(internalSignal);
      }
      if (changed) {
        internalSignals
          ..clear()
          ..addAll(reducedInternalSignals);
        continue;
      }

      final reducedAssignments = <SynthAssignment>[];
      for (final assignment in assignments) {
        if ((assignment.src.declarationCleared ||
                assignment.dst.declarationCleared) &&
            !(assignment.src.isNet || assignment.dst.isNet)) {
          changed = true;
        } else if (assignment is PartialSynthAssignment &&
            !assignment.src.hasSrcConnectionsPresent() &&
            !assignment.src.isStructPortElement(module) &&
            assignment.src.isClearable) {
          assignment.src.clearDeclaration();
          changed = true;
        } else {
          reducedAssignments.add(assignment);
        }
      }
      if (changed) {
        assignments
          ..clear()
          ..addAll(reducedAssignments);
        continue;
      }

      for (final subModuleInstantiation in subModuleInstantiations.where(
        (e) => e.needsInstantiation,
      )) {
        final subModule = subModuleInstantiation.module;

        if (subModule is SystemVerilog && subModule.isWiresOnly) {
          final inputs = {
            ...subModuleInstantiation.inputMapping,
            ...subModuleInstantiation.inOutMapping,
          };
          final outputs = {
            ...subModuleInstantiation.outputMapping,
            ...subModuleInstantiation.inOutMapping,
          };

          // if all the inputs or all the outputs are not used, we can remove
          // the module

          final allOutputsUnused = outputs.values.every(
            (output) =>
                output.declarationCleared ||
                (output.isClearable &&
                    !output.isStructPortElement() &&
                    !output.hasDstConnectionsPresent()),
          );
          if (allOutputsUnused) {
            subModuleInstantiation.clearInstantiation();
            changed = true;
            continue;
          }

          final allInputsUnused = inputs.values.every(
            (input) =>
                input.declarationCleared ||
                (input.isClearable &&
                    !input.isStructPortElement() &&
                    !input.hasSrcConnectionsPresent()),
          );
          if (allInputsUnused) {
            subModuleInstantiation.clearInstantiation();
            changed = true;
            continue;
          }
        }
      }
    }
  }

  /// Updates all sub-module instantiations with information about which
  /// [SynthLogic] should be used for their ports.
  void _assignSubmodulePortMapping() {
    for (final submoduleInstantiation in subModuleInstantiations) {
      for (final inputName in submoduleInstantiation.module.inputs.keys) {
        final orig = submoduleInstantiation.inputMapping[inputName]!;
        submoduleInstantiation.setInputMapping(
          inputName,
          orig.replacement ?? orig,
          replace: true,
        );
      }

      for (final outputName in submoduleInstantiation.module.outputs.keys) {
        final orig = submoduleInstantiation.outputMapping[outputName]!;
        submoduleInstantiation.setOutputMapping(
          outputName,
          orig.replacement ?? orig,
          replace: true,
        );
      }

      for (final inOutName in submoduleInstantiation.module.inOuts.keys) {
        final orig = submoduleInstantiation.inOutMapping[inOutName]!;
        submoduleInstantiation.setInOutMapping(
          inOutName,
          orig.replacement ?? orig,
          replace: true,
        );
      }
    }
  }

  /// Picks names of signals and sub-modules.
  ///
  /// Signal names are selected through [Namer.signalNameOfBest] or kept as
  /// literal constants. Submodule names are selected through
  /// [Namer.instanceNameOf]. All non-constant names share a single namespace
  /// managed by the module's [Namer].
  void _pickNames() {
    // first ports get priority
    // Name allocation order matters -- earlier claims receive the unsuffixed
    // name when there are collisions. Weak-name claimants are intentionally
    // deferred so emitted objects receive 1st chance at the shortest basenames:
    //   1. Ports (reserved by _initNamespace, claimed via signalName)
    //   2. Reserved submodule instances
    //   3. Reserved internal signals with strong claims
    //   4. Non-reserved submodule instances with strong claims
    //   5. Non-reserved internal signals with strong claims
    //   6. Weak submodule instances
    //   7. Weak internal signals
    for (final input in inputs) {
      input.pickName();
    }
    for (final output in outputs) {
      output.pickName();
    }
    for (final inOut in inOuts) {
      inOut.pickName();
    }

    // Reserved submodule instances first (they assert their exact name).
    for (final submodule in subModuleInstantiations) {
      if (submodule.module.reserveName) {
        submodule.pickName(module);
        assert(submodule.module.name == submodule.name,
            'Expect reserved names to retain their name.');
      }
    }

    // Reserved internal signals next.
    final nonReservedSignals = <SynthLogic>[];
    final weakSignals = <SynthLogic>[];
    for (final signal in internalSignals) {
      if (_weakNameClaimSignals.contains(signal)) {
        weakSignals.add(signal);
      } else if (signal.isReserved) {
        signal.pickName();
      } else {
        nonReservedSignals.add(signal);
      }
    }

    // Then non-reserved submodule instances with strong name claims.
    final weakSubmodules = <SynthSubModuleInstantiation>[];
    for (final submodule in subModuleInstantiations) {
      if (submodule.module.reserveName) {
        continue;
      }
      if (_weakNameClaimSubmodules.contains(submodule)) {
        weakSubmodules.add(submodule);
      } else if (submodule.needsInstantiation) {
        submodule.pickName(module);
      }
    }

    // Then the rest of the internal signals with strong name claims.
    for (final signal in nonReservedSignals) {
      signal.pickName();
    }

    // Finally, weak claims reserve stable names after emitted objects have
    // had first chance at the shortest basenames.
    for (final submodule in weakSubmodules) {
      submodule.pickName(module);
    }
    for (final signal in weakSignals) {
      signal.pickName();
    }
  }

  /// Merges bit blasted array assignments into fewer assignments when they are
  /// full array-to-array assignments or contiguous same-offset array ranges.
  void _collapseArrays() {
    final boringArrayPairs = <(SynthLogic, SynthLogic)>[];

    var prevAssignmentCount = 0;
    while (prevAssignmentCount != assignments.length) {
      final reducedAssignments = <SynthAssignment>[];

      final groupedAssignments =
          <(SynthLogic, SynthLogic), List<SynthAssignment>>{};

      for (final assignment in assignments) {
        final src = assignment.src;
        final dst = assignment.dst;

        if (src is SynthLogicArrayElement && dst is SynthLogicArrayElement) {
          final srcArray = src.parentArray.resolved;
          final dstArray = dst.parentArray.resolved;

          assert(srcArray.logics.length == 1, 'should be 1 name for the array');
          assert(dstArray.logics.length == 1, 'should be 1 name for the array');

          if (boringArrayPairs.contains((srcArray, dstArray))) {
            reducedAssignments.add(assignment);
          } else {
            groupedAssignments[(srcArray, dstArray)] ??= [];
            groupedAssignments[(srcArray, dstArray)]!.add(assignment);
          }
        } else {
          reducedAssignments.add(assignment);
        }
      }

      for (final MapEntry(key: (srcArray, dstArray), value: arrAssignments)
          in groupedAssignments.entries) {
        // first requirement is that all elements have been assigned
        var shouldMerge = srcArray.logics.first.elements.length ==
                dstArray.logics.first.elements.length &&
            arrAssignments.length == srcArray.logics.first.elements.length;

        if (shouldMerge) {
          // only check each element if the lengths match
          for (final arrAssignment in arrAssignments) {
            final arrAssignmentSrc =
                (arrAssignment.src as SynthLogicArrayElement).logic;
            final arrAssignmentDst =
                (arrAssignment.dst as SynthLogicArrayElement).logic;

            if (arrAssignmentSrc.arrayIndex! != arrAssignmentDst.arrayIndex!) {
              shouldMerge = false;
              break;
            }
          }
        }

        if (shouldMerge) {
          reducedAssignments.add(SynthAssignment(srcArray, dstArray));
        } else {
          reducedAssignments.addAll(
            _collapseArrayElementRanges(srcArray, dstArray, arrAssignments),
          );
          boringArrayPairs.add((srcArray, dstArray));
        }
      }

      prevAssignmentCount = assignments.length;
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }

  /// Collapses contiguous same-offset element assignments into range
  /// assignments, when the array shapes are simple enough to render as packed
  /// ranges across the first dimension.
  List<SynthAssignment> _collapseArrayElementRanges(
    SynthLogic srcArray,
    SynthLogic dstArray,
    List<SynthAssignment> arrAssignments,
  ) {
    if (!_canCollapseArrayElementRanges(srcArray, dstArray) ||
        arrAssignments.length < 2) {
      return arrAssignments;
    }

    int srcIndex(SynthAssignment assignment) =>
        (assignment.src as SynthLogicArrayElement).logic.arrayIndex!;
    int dstIndex(SynthAssignment assignment) =>
        (assignment.dst as SynthLogicArrayElement).logic.arrayIndex!;

    final seenDstIndices = <int>{};
    final assignmentsByOffset = <int, List<SynthAssignment>>{};
    for (final assignment in arrAssignments) {
      final srcElementIndex = srcIndex(assignment);
      final dstElementIndex = dstIndex(assignment);
      if (!seenDstIndices.add(dstElementIndex)) {
        return arrAssignments;
      }
      assignmentsByOffset
          .putIfAbsent(dstElementIndex - srcElementIndex, () => [])
          .add(assignment);
    }

    final collapsedAssignments = <({int dstLowerIndex, SynthAssignment a})>[];

    void addRun(List<SynthAssignment> group, int start, int end) {
      if (end == start) {
        final assignment = group[start];
        collapsedAssignments.add((
          dstLowerIndex: dstIndex(assignment),
          a: assignment,
        ));
        return;
      }

      final first = group[start];
      final last = group[end];
      collapsedAssignments.add((
        dstLowerIndex: dstIndex(first),
        a: RangeSynthAssignment(
          srcArray,
          dstArray,
          srcUpperIndex: srcIndex(last),
          srcLowerIndex: srcIndex(first),
          dstUpperIndex: dstIndex(last),
          dstLowerIndex: dstIndex(first),
        ),
      ));
    }

    for (final group in assignmentsByOffset.values) {
      group.sort((a, b) => dstIndex(a).compareTo(dstIndex(b)));

      var start = 0;
      for (var index = 1; index < group.length; index++) {
        final previous = group[index - 1];
        final current = group[index];
        final continuesRun = dstIndex(current) == dstIndex(previous) + 1 &&
            srcIndex(current) == srcIndex(previous) + 1;
        if (!continuesRun) {
          addRun(group, start, index - 1);
          start = index;
        }
      }
      addRun(group, start, group.length - 1);
    }

    collapsedAssignments.sort(
      (a, b) => a.dstLowerIndex.compareTo(b.dstLowerIndex),
    );
    return [for (final assignment in collapsedAssignments) assignment.a];
  }

  /// Whether [srcArray] and [dstArray] are safe for range assignment collapse.
  bool _canCollapseArrayElementRanges(
    SynthLogic srcArray,
    SynthLogic dstArray,
  ) {
    if (srcArray == dstArray || srcArray.isNet || dstArray.isNet) {
      return false;
    }
    if (srcArray.logics.length != 1 || dstArray.logics.length != 1) {
      return false;
    }
    final srcLogic = srcArray.logics.first;
    final dstLogic = dstArray.logics.first;
    if (srcLogic is! LogicArray || dstLogic is! LogicArray) {
      return false;
    }

    return srcLogic.dimensions.length == 1 &&
        dstLogic.dimensions.length == 1 &&
        srcLogic.elementWidth == 1 &&
        dstLogic.elementWidth == 1 &&
        srcLogic.numUnpackedDimensions == 0 &&
        dstLogic.numUnpackedDimensions == 0;
  }

  /// Collapses simple contiguous packed range assignments that are represented
  /// as bit-by-bit assignments, such as non-net bus subsets feeding array
  /// elements.
  void _collapseSimpleRangeAssignments() {
    final busSubsetRanges = _busSubsetSourceRanges();
    if (busSubsetRanges.isEmpty) {
      return;
    }

    final generatedSubsetSets = _generatedSubsetIntermediateSets();
    final generatedSubsetCandidates = generatedSubsetSets.candidates;
    final generatedSubsetIntermediates = generatedSubsetSets.intermediates;

    final swizzleInputSignals = {
      for (final instantiation in subModuleInstantiations)
        if (instantiation.module is Swizzle &&
            !(instantiation.module as Swizzle).isNet)
          ...instantiation.inputMapping.values.map((signal) => signal.resolved),
    };
    final assignmentsBySourceBase = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsBySourceBase
          .putIfAbsent(_referenceBase(assignment.src), () => [])
          .add(assignment);
    }
    final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
    final assignmentsBySource = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByDestination
          .putIfAbsent(assignment.dst.resolved, () => [])
          .add(assignment);
      assignmentsBySource
          .putIfAbsent(assignment.src.resolved, () => [])
          .add(assignment);
    }
    final knownSourceRanges = {
      for (final entry in busSubsetRanges.entries) entry.key: entry.value.range,
    };

    final reducedAssignments = <SynthAssignment>[];
    final groupedCandidates = <(SynthLogic, SynthLogic, int),
        List<
            ({
              SynthAssignment assignment,
              _SynthRangeRef src,
              _SynthRangeRef dst,
              SynthSubModuleInstantiation? sourceSubmodule,
              SynthLogic? sourceSignal,
            })>>{};

    for (final assignment in assignments) {
      if (assignment is PartialSynthAssignment) {
        reducedAssignments.add(assignment);
        continue;
      }

      final src = _simpleAssignmentSourceRange(assignment, busSubsetRanges);
      final resolvedSrc = src == null
          ? null
          : (
              range: _resolveKnownRangeThroughFullWidthDrivers(
                src.range,
                assignmentsByDestination,
                knownSourceRanges,
              ),
              sourceSubmodule: src.sourceSubmodule,
              sourceSignal: src.sourceSignal,
            );
      final dst = _simpleAssignmentDestinationRange(assignment);
      if (resolvedSrc == null ||
          dst == null ||
          resolvedSrc.range.width != 1 ||
          dst.width != 1 ||
          resolvedSrc.range.base == dst.base ||
          (resolvedSrc.sourceSubmodule != null &&
              resolvedSrc.range.lower != dst.lower &&
              !generatedSubsetIntermediates.contains(dst.base)) ||
          (resolvedSrc.sourceSubmodule != null &&
              !_hasOnlySwizzleConsumers(
                dst.base,
                assignmentsBySourceBase,
                swizzleInputSignals,
              )) ||
          !_canUsePackedRangeBase(resolvedSrc.range.base) ||
          !_canUsePackedRangeBase(dst.base)) {
        reducedAssignments.add(assignment);
        continue;
      }

      groupedCandidates.putIfAbsent((
        resolvedSrc.range.base,
        dst.base,
        dst.lower - resolvedSrc.range.lower
      ), () => []).add((
        assignment: assignment,
        src: resolvedSrc.range,
        dst: dst,
        sourceSubmodule: resolvedSrc.sourceSubmodule,
        sourceSignal: resolvedSrc.sourceSignal,
      ));
    }

    final fullyCoveredGeneratedSubsets = <SynthLogic>{};
    final generatedSubsetBits = <SynthLogic, Set<int>>{};
    for (final group in groupedCandidates.values) {
      for (final candidate in group) {
        if (generatedSubsetCandidates.contains(candidate.dst.base)) {
          generatedSubsetBits
              .putIfAbsent(candidate.dst.base, () => {})
              .add(candidate.dst.lower);
        }
      }
    }
    for (final entry in generatedSubsetBits.entries) {
      if (entry.value.length == entry.key.width &&
          Iterable<int>.generate(entry.key.width).every(entry.value.contains)) {
        fullyCoveredGeneratedSubsets.add(entry.key);
      }
    }

    var changed = false;
    for (final group in groupedCandidates.values) {
      group.sort((a, b) => a.dst.lower.compareTo(b.dst.lower));

      var start = 0;
      for (var index = 1; index < group.length; index++) {
        final previous = group[index - 1];
        final current = group[index];
        final continuesRun = current.dst.lower == previous.dst.lower + 1 &&
            current.src.lower == previous.src.lower + 1;
        if (!continuesRun) {
          changed |= _addSimpleRangeRun(
            reducedAssignments,
            group,
            start,
            index - 1,
            generatedSubsetCandidates,
            generatedSubsetIntermediates,
            fullyCoveredGeneratedSubsets,
          );
          start = index;
        }
      }
      changed |= _addSimpleRangeRun(
        reducedAssignments,
        group,
        start,
        group.length - 1,
        generatedSubsetCandidates,
        generatedSubsetIntermediates,
        fullyCoveredGeneratedSubsets,
      );
    }

    if (changed) {
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }

  bool _hasOnlySwizzleConsumers(
    SynthLogic base,
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySourceBase,
    Set<SynthLogic> swizzleInputSignals,
  ) {
    final consumers = assignmentsBySourceBase[base] ?? const [];
    return consumers.isNotEmpty &&
        consumers.every(
          (assignment) => swizzleInputSignals.contains(assignment.dst.resolved),
        );
  }

  bool _addSimpleRangeRun(
    List<SynthAssignment> reducedAssignments,
    List<
            ({
              SynthAssignment assignment,
              _SynthRangeRef src,
              _SynthRangeRef dst,
              SynthSubModuleInstantiation? sourceSubmodule,
              SynthLogic? sourceSignal,
            })>
        group,
    int start,
    int end,
    Set<SynthLogic> generatedSubsetCandidates,
    Set<SynthLogic> generatedSubsetIntermediates,
    Set<SynthLogic> fullyCoveredGeneratedSubsets,
  ) {
    if (start == end) {
      reducedAssignments.add(group[start].assignment);
      return false;
    }

    final first = group[start];
    final last = group[end];
    if (generatedSubsetCandidates.contains(first.dst.base) &&
        !fullyCoveredGeneratedSubsets.contains(first.dst.base) &&
        (!generatedSubsetIntermediates.contains(first.dst.base) ||
            !group.getRange(start, end + 1).every((candidate) =>
                _canPartiallyCollapseGeneratedSubsetSource(
                    candidate.src.base)))) {
      for (var index = start; index <= end; index++) {
        reducedAssignments.add(group[index].assignment);
      }
      return false;
    }

    reducedAssignments.add(
      RangeSynthAssignment(
        first.src.base,
        first.dst.base,
        srcUpperIndex: last.src.upper,
        srcLowerIndex: first.src.lower,
        dstUpperIndex: last.dst.upper,
        dstLowerIndex: first.dst.lower,
      ),
    );
    for (var index = start; index <= end; index++) {
      group[index].sourceSubmodule?.clearInstantiation();
      group[index].sourceSignal?.clearDeclaration();
    }
    return true;
  }

  bool _canPartiallyCollapseGeneratedSubsetSource(SynthLogic sourceBase) =>
      _isLiveRangeSource(sourceBase);

  bool _isLiveRangeSource(SynthLogic sourceBase) =>
      !sourceBase.isConstant &&
      (sourceBase.hasSrcConnectionsPresent() ||
          sourceBase.isStructPortElement(module) ||
          !internalSignals.contains(sourceBase) ||
          !sourceBase.isClearable);

  /// Composes temporary bus slices through full-width assignments into wide
  /// array-element destinations.
  void _collapseWideArrayElementRangeSources() {
    final busSubsetRanges = _busSubsetSourceRanges();
    if (busSubsetRanges.isEmpty) {
      return;
    }

    final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
    final assignmentsBySource = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByDestination
          .putIfAbsent(assignment.dst.resolved, () => [])
          .add(assignment);
      assignmentsBySource
          .putIfAbsent(assignment.src.resolved, () => [])
          .add(assignment);
    }
    final knownSourceRanges = {
      for (final entry in busSubsetRanges.entries) entry.key: entry.value.range,
    };

    var changed = false;
    final updatedAssignments = <SynthAssignment>[];
    for (final assignment in assignments) {
      if (assignment is PartialSynthAssignment ||
          assignment.dst.resolved is! SynthLogicArrayElement) {
        updatedAssignments.add(assignment);
        continue;
      }

      final busSubsetRange = busSubsetRanges[assignment.src.resolved];
      if (busSubsetRange == null) {
        updatedAssignments.add(assignment);
        continue;
      }
      if (!internalSignals.contains(busSubsetRange.range.base) ||
          !busSubsetRange.range.base.isClearable) {
        updatedAssignments.add(assignment);
        continue;
      }

      final dst = assignment.dst.resolved;
      if (dst.width <= 1) {
        updatedAssignments.add(assignment);
        continue;
      }

      final src = _resolveKnownRangeThroughFullWidthDrivers(
        busSubsetRange.range,
        assignmentsByDestination,
        knownSourceRanges,
      );
      if (src.base == dst ||
          src.width != dst.width ||
          !_canUsePackedRangeBase(src.base) ||
          dst.isNet ||
          dst.isConstant) {
        updatedAssignments.add(assignment);
        continue;
      }

      updatedAssignments.add(
        RangeSynthAssignment(
          src.base,
          dst,
          srcUpperIndex: src.upper,
          srcLowerIndex: src.lower,
          dstUpperIndex: dst.width - 1,
          dstLowerIndex: 0,
        ),
      );
      if (assignmentsBySource[assignment.src.resolved]?.length == 1) {
        busSubsetRange.inst.clearInstantiation();
        assignment.src.clearDeclaration();
      }
      changed = true;
    }

    if (changed) {
      assignments
        ..clear()
        ..addAll(updatedAssignments);
    }
  }

  Map<SynthLogic, ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>
      _busSubsetSourceRanges() {
    final directRanges = <SynthLogic,
        ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>{};
    final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByDestination
          .putIfAbsent(assignment.dst.resolved, () => [])
          .add(assignment);
    }

    for (final instantiation in subModuleInstantiations) {
      final module = instantiation.module;
      if (module is! BusSubset ||
          module.original.isNet ||
          module.startIndex > module.endIndex) {
        continue;
      }

      final original = instantiation.inputMapping[module.original.name];
      final subset = instantiation.outputMapping[module.subset.name];
      if (original == null ||
          subset == null ||
          original.isNet ||
          subset.isNet ||
          !_canUsePackedRangeBase(original.resolved)) {
        continue;
      }

      directRanges[subset.resolved] = (
        range: _SynthRangeRef(
          original.resolved,
          module.startIndex,
          module.endIndex,
        ),
        inst: instantiation,
      );
    }

    final ranges = <SynthLogic,
        ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>{};
    for (final entry in directRanges.entries) {
      final resolvedRange = _resolveFullWidthDrivenRange(
        entry.value.range,
        assignmentsByDestination,
        directRanges,
      );
      if (!_canUsePackedRangeBase(resolvedRange.base)) {
        continue;
      }

      ranges[entry.key] = (range: resolvedRange, inst: entry.value.inst);
    }
    return ranges;
  }

  _SynthRangeRef _resolveFullWidthDrivenRange(
    _SynthRangeRef range,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
    Map<SynthLogic, ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>
        directRanges, [
    Set<SynthLogic> visiting = const {},
  ]) {
    if (visiting.contains(range.base)) {
      return range;
    }

    final sourceRange = _singleFullWidthSourceRange(
      range.base,
      assignmentsByDestination,
      directRanges,
      {...visiting, range.base},
    );
    if (sourceRange == null) {
      return range;
    }

    return _SynthRangeRef(
      sourceRange.base,
      sourceRange.lower + range.lower,
      sourceRange.lower + range.upper,
    );
  }

  _SynthRangeRef? _singleFullWidthSourceRange(
    SynthLogic signal,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
    Map<SynthLogic, ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>
        directRanges,
    Set<SynthLogic> visiting,
  ) {
    final driver = _singleFullWidthAssignment(signal, assignmentsByDestination);
    if (driver == null) {
      return null;
    }

    if (driver is RangeSynthAssignment) {
      return _SynthRangeRef(
        driver.src.resolved,
        driver.srcLowerIndex,
        driver.srcUpperIndex,
      );
    }

    final driverSrc = driver.src.resolved;
    final directRange = directRanges[driverSrc];
    if (directRange != null) {
      return _resolveFullWidthDrivenRange(
        directRange.range,
        assignmentsByDestination,
        directRanges,
        visiting,
      );
    }

    return _SynthRangeRef(driverSrc, 0, driverSrc.width - 1);
  }

  SynthAssignment? _singleFullWidthAssignment(
    SynthLogic signal,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
  ) {
    final drivers = assignmentsByDestination[signal.resolved];
    if (drivers == null || drivers.length != 1) {
      return null;
    }

    final driver = drivers.single;
    if (driver is RangeSynthAssignment) {
      if (driver.dstLowerIndex != 0 ||
          driver.dstUpperIndex != signal.width - 1 ||
          driver.width != signal.width) {
        return null;
      }
      return driver;
    }

    if (driver is PartialSynthAssignment || driver.width != signal.width) {
      return null;
    }

    return driver;
  }

  ({
    _SynthRangeRef range,
    SynthSubModuleInstantiation? sourceSubmodule,
    SynthLogic? sourceSignal,
  })? _simpleAssignmentSourceRange(
    SynthAssignment assignment,
    Map<SynthLogic, ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>
        busSubsetRanges,
  ) {
    final src = assignment.src.resolved;
    final busSubsetRange = busSubsetRanges[src];
    if (busSubsetRange != null) {
      return (
        range: busSubsetRange.range,
        sourceSubmodule: busSubsetRange.inst,
        sourceSignal: src,
      );
    }

    final arrayElementRange = _arrayElementRange(src);
    if (arrayElementRange == null) {
      return null;
    }
    return (
      range: arrayElementRange,
      sourceSubmodule: null,
      sourceSignal: null,
    );
  }

  _SynthRangeRef? _simpleAssignmentDestinationRange(
          SynthAssignment assignment) =>
      _arrayElementRange(assignment.dst.resolved);

  _SynthRangeRef? _arrayElementRange(SynthLogic signal) {
    if (signal is! SynthLogicArrayElement) {
      return null;
    }
    final parentArray = signal.parentArray.resolved;
    if (!_canUsePackedRangeBase(parentArray)) {
      return null;
    }
    final index = signal.logic.arrayIndex!;
    return _SynthRangeRef(parentArray, index, index);
  }

  bool _canUsePackedRangeBase(SynthLogic base) {
    if (base.isNet || base.isConstant) {
      return false;
    }
    if (!base.isArray) {
      return true;
    }
    if (base.logics.length != 1) {
      return false;
    }
    final logic = base.logics.first;
    return logic is LogicArray &&
        logic.dimensions.length == 1 &&
        logic.elementWidth == 1 &&
        logic.numUnpackedDimensions == 0;
  }

  /// Composes single-use chained range assignments through an internal
  /// intermediate.
  void _collapseChainedRangeAssignments() {
    final generatedSubsetIntermediates = _generatedSubsetIntermediates();
    var changed = true;

    while (changed) {
      changed = false;

      final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
      final assignmentsBySource = <SynthLogic, List<SynthAssignment>>{};
      for (final assignment in assignments) {
        assignmentsByDestination
            .putIfAbsent(_referenceBase(assignment.dst), () => [])
            .add(assignment);
        assignmentsBySource
            .putIfAbsent(_referenceBase(assignment.src), () => [])
            .add(assignment);
      }

      for (final producer
          in assignments.whereType<PartialSynthAssignment>().toList()) {
        final intermediate = producer.dst.resolved;
        final producers = assignmentsByDestination[intermediate];
        final consumers = assignmentsBySource[intermediate];

        if (producers?.length != 1 || consumers?.length != 1) {
          continue;
        }
        if (producers!.single != producer) {
          continue;
        }

        final consumer = consumers!.single;

        final replacement = _composeChainedRangeAssignment(
          producer: producer,
          consumer: consumer,
          intermediate: intermediate,
          generatedSubsetIntermediates: generatedSubsetIntermediates,
        );
        if (replacement == null) {
          continue;
        }

        final updatedAssignments = <SynthAssignment>[];
        for (final assignment in assignments) {
          if (assignment == producer) {
            continue;
          }
          updatedAssignments
              .add(assignment == consumer ? replacement : assignment);
        }
        intermediate.clearDeclaration();
        assignments
          ..clear()
          ..addAll(updatedAssignments);
        changed = true;
        break;
      }
    }
  }

  RangeSynthAssignment? _composeChainedRangeAssignment({
    required PartialSynthAssignment producer,
    required SynthAssignment consumer,
    required SynthLogic intermediate,
    required Set<SynthLogic> generatedSubsetIntermediates,
  }) {
    if (!_isRangeChainIntermediate(intermediate)) {
      return null;
    }

    final producerSrc = _assignmentSourceRange(producer);
    final producerDst = _assignmentDestinationRange(producer);
    final consumerSrc = _assignmentSourceRange(consumer);
    final consumerDst = _assignmentDestinationRange(consumer);

    if (producerDst.base != intermediate || consumerSrc.base != intermediate) {
      return null;
    }
    if (producerSrc.base == consumerDst.base ||
        producerSrc.base.isNet ||
        consumerDst.base.isNet ||
        producerSrc.base.isConstant ||
        consumerDst.base.isConstant) {
      return null;
    }

    late final _SynthRangeRef replacementSrc;
    late final _SynthRangeRef replacementDst;
    if (consumer is PartialSynthAssignment) {
      if (!producerDst.contains(consumerSrc)) {
        return null;
      }

      final sourceLower =
          producerSrc.lower + (consumerSrc.lower - producerDst.lower);
      final sourceUpper =
          producerSrc.lower + (consumerSrc.upper - producerDst.lower);
      replacementSrc =
          _SynthRangeRef(producerSrc.base, sourceLower, sourceUpper);
      replacementDst = consumerDst;
    } else {
      if (!consumerSrc.contains(producerDst)) {
        return null;
      }
      final producerCoversWholeConsumer =
          producerDst.lower == consumerSrc.lower &&
              producerDst.upper == consumerSrc.upper;
      if (!producerCoversWholeConsumer) {
        if (!generatedSubsetIntermediates.contains(intermediate) ||
            consumerDst.base is SynthLogicArrayElement) {
          return null;
        }
      }

      final dstLower =
          consumerDst.lower + (producerDst.lower - consumerSrc.lower);
      final dstUpper =
          consumerDst.lower + (producerDst.upper - consumerSrc.lower);
      replacementSrc = producerSrc;
      replacementDst = _SynthRangeRef(consumerDst.base, dstLower, dstUpper);
    }

    if (replacementSrc.width != replacementDst.width ||
        replacementSrc.lower < 0 ||
        replacementSrc.upper >= replacementSrc.base.width ||
        replacementDst.lower < 0 ||
        replacementDst.upper >= replacementDst.base.width) {
      return null;
    }

    return RangeSynthAssignment(
      replacementSrc.base,
      replacementDst.base,
      srcUpperIndex: replacementSrc.upper,
      srcLowerIndex: replacementSrc.lower,
      dstUpperIndex: replacementDst.upper,
      dstLowerIndex: replacementDst.lower,
    );
  }

  /// Collapses a generated `assignSubset` array that is only consumed by a
  /// full packed swizzle into a range assignment to the swizzle output.
  void _collapseGeneratedSubsetSwizzleRangeAssignments() {
    final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
    final assignmentsBySourceBase = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByDestination
          .putIfAbsent(assignment.dst.resolved, () => [])
          .add(assignment);
      assignmentsBySourceBase
          .putIfAbsent(_referenceBase(assignment.src), () => [])
          .add(assignment);
    }

    final allSwizzleSourceRanges =
        _fullPackedSwizzleSourceRanges(assignmentsByDestination);
    final generatedSubsetIntermediates = _generatedSubsetIntermediatesFrom(
      allSwizzleSourceRanges,
      assignmentsBySourceBase,
    );
    final swizzleSourceRanges = {
      for (final entry in allSwizzleSourceRanges.entries)
        if (generatedSubsetIntermediates.contains(entry.value.range.base))
          entry.key: entry.value,
    };
    if (swizzleSourceRanges.isEmpty) {
      return;
    }

    final swizzlesByBase = <SynthLogic,
        List<
            ({
              SynthLogic output,
              _SynthRangeRef range,
              SynthSubModuleInstantiation inst,
              List<SynthAssignment> inputAssignments,
            })>>{};
    for (final entry in swizzleSourceRanges.entries) {
      swizzlesByBase.putIfAbsent(entry.value.range.base, () => []).add((
        output: entry.key,
        range: entry.value.range,
        inst: entry.value.inst,
        inputAssignments: entry.value.inputAssignments,
      ));
    }

    final assignmentsByBaseDestination = <SynthLogic, List<SynthAssignment>>{};
    final assignmentsBySource = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByBaseDestination
          .putIfAbsent(_referenceBase(assignment.dst), () => [])
          .add(assignment);
      assignmentsBySource
          .putIfAbsent(_referenceBase(assignment.src), () => [])
          .add(assignment);
    }
    final knownSourceRanges = {
      for (final entry in _busSubsetSourceRanges().entries)
        entry.key: entry.value.range,
    };

    final replacements = <SynthAssignment, SynthAssignment>{};
    final consumedAssignments = <SynthAssignment>{};
    for (final entry in swizzlesByBase.entries) {
      final intermediate = entry.key;
      final swizzles = entry.value;
      final swizzle = swizzles.singleOrNull;
      final sourceUsers = assignmentsBySource[intermediate] ?? const [];
      final producers = assignmentsByBaseDestination[intermediate]
          ?.whereType<PartialSynthAssignment>()
          .toList();
      if (swizzles.length != 1 ||
          swizzle == null ||
          producers == null ||
          producers.isEmpty ||
          producers.length != assignmentsByDestination[intermediate]?.length ||
          sourceUsers.any(
            (sourceUser) => !swizzle.inputAssignments.contains(sourceUser),
          )) {
        continue;
      }

      if (!_isRangeChainIntermediate(
        intermediate,
        allowedInstantiation: swizzle.inst,
      )) {
        continue;
      }

      final output = swizzle.output.resolved;
      if (output.isNet || output.isConstant) {
        continue;
      }

      final producerReplacements = <SynthAssignment, SynthAssignment>{};
      final seenDestinationBits = <int>{};
      var canReplaceAll = true;
      for (final producer in producers) {
        final producerSrc = _resolveKnownRangeThroughFullWidthDrivers(
          _assignmentSourceRange(producer),
          assignmentsByDestination,
          knownSourceRanges,
        );
        final producerDst = _assignmentDestinationRange(producer);
        if (producerDst.base != intermediate ||
            !swizzle.range.contains(producerDst) ||
            producerSrc.base == output ||
            producerSrc.base.isNet ||
            producerSrc.base.isConstant) {
          canReplaceAll = false;
          break;
        }
        if (!_isLiveRangeSource(producerSrc.base)) {
          canReplaceAll = false;
          break;
        }

        final dstLower = producerDst.lower - swizzle.range.lower;
        final dstUpper = producerDst.upper - swizzle.range.lower;
        if (producerSrc.width != dstUpper - dstLower + 1 ||
            dstLower < 0 ||
            dstUpper >= output.width) {
          canReplaceAll = false;
          break;
        }
        for (var index = dstLower; index <= dstUpper; index++) {
          if (!seenDestinationBits.add(index)) {
            canReplaceAll = false;
            break;
          }
        }
        if (!canReplaceAll) {
          break;
        }

        producerReplacements[producer] = RangeSynthAssignment(
          producerSrc.base,
          output,
          srcUpperIndex: producerSrc.upper,
          srcLowerIndex: producerSrc.lower,
          dstUpperIndex: dstUpper,
          dstLowerIndex: dstLower,
        );
      }
      if (!canReplaceAll) {
        continue;
      }
      if (seenDestinationBits.length != output.width &&
          (output.logics.any((logic) => logic.isArrayMember) ||
              _hasArrayMemberConsumer(output, assignmentsBySource))) {
        continue;
      }

      replacements.addAll(producerReplacements);
      consumedAssignments.addAll(swizzle.inputAssignments);
      intermediate.clearDeclaration();
      swizzle.inst.clearInstantiation();
    }

    if (replacements.isNotEmpty) {
      final updatedAssignments = [
        for (final assignment in assignments)
          if (replacements.containsKey(assignment))
            replacements[assignment]!
          else if (!consumedAssignments.contains(assignment))
            assignment,
      ];
      assignments
        ..clear()
        ..addAll(updatedAssignments);
    }
  }

  bool _hasArrayMemberConsumer(
    SynthLogic source,
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySource,
  ) {
    final consumers = assignmentsBySource[source] ?? const [];
    return consumers.any(
      (assignment) =>
          assignment.dst is SynthLogicArrayElement ||
          assignment.dst.resolved.logics.any((logic) => logic.isArrayMember),
    );
  }

  _SynthRangeRef _resolveKnownRangeThroughFullWidthDrivers(
    _SynthRangeRef range,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
    Map<SynthLogic, _SynthRangeRef> knownSourceRanges, [
    Set<SynthLogic> visiting = const {},
  ]) {
    if (visiting.contains(range.base) || !range.base.isClearable) {
      return range;
    }

    final driver = _singleFullWidthAssignment(
      range.base,
      assignmentsByDestination,
    );
    if (driver == null) {
      return range;
    }

    final sourceRange = driver is RangeSynthAssignment
        ? _SynthRangeRef(
            driver.src.resolved,
            driver.srcLowerIndex,
            driver.srcUpperIndex,
          )
        : knownSourceRanges[driver.src.resolved] ??
            _SynthRangeRef(driver.src.resolved, 0, driver.src.width - 1);

    final resolvedSourceRange = _resolveKnownRangeThroughFullWidthDrivers(
      sourceRange,
      assignmentsByDestination,
      knownSourceRanges,
      {...visiting, range.base},
    );
    if (resolvedSourceRange.width != range.base.width) {
      return range;
    }

    return _SynthRangeRef(
      resolvedSourceRange.base,
      resolvedSourceRange.lower + range.lower,
      resolvedSourceRange.lower + range.upper,
    );
  }

  ({Set<SynthLogic> candidates, Set<SynthLogic> intermediates})
      _generatedSubsetIntermediateSets() {
    final assignmentsByDestination = <SynthLogic, List<SynthAssignment>>{};
    final assignmentsBySourceBase = <SynthLogic, List<SynthAssignment>>{};
    for (final assignment in assignments) {
      assignmentsByDestination
          .putIfAbsent(assignment.dst.resolved, () => [])
          .add(assignment);
      assignmentsBySourceBase
          .putIfAbsent(_referenceBase(assignment.src), () => [])
          .add(assignment);
    }

    final swizzleSourceRanges =
        _fullPackedSwizzleSourceRanges(assignmentsByDestination);
    final candidates = {
      for (final entry in swizzleSourceRanges.entries)
        if (_isGeneratedSubsetIntermediateCandidate(entry.value.range.base))
          entry.value.range.base,
    };

    return (
      candidates: candidates,
      intermediates: _generatedSubsetIntermediatesFrom(
        swizzleSourceRanges,
        assignmentsBySourceBase,
      ),
    );
  }

  Set<SynthLogic> _generatedSubsetIntermediates() =>
      _generatedSubsetIntermediateSets().intermediates;

  Set<SynthLogic> _generatedSubsetIntermediatesFrom(
    Map<
            SynthLogic,
            ({
              _SynthRangeRef range,
              SynthSubModuleInstantiation inst,
              List<SynthAssignment> inputAssignments,
            })>
        swizzleSourceRanges,
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySourceBase,
  ) {
    final generatedSubsetIntermediates = <SynthLogic>{};
    for (final entry in swizzleSourceRanges.entries) {
      final intermediate = entry.value.range.base;
      if (_isGeneratedSubsetIntermediateCandidate(intermediate) &&
          _hasInternalFullWidthSwizzleConsumer(
            entry.key,
            assignmentsBySourceBase,
          )) {
        generatedSubsetIntermediates.add(intermediate);
      }
    }

    return generatedSubsetIntermediates;
  }

  Map<
      SynthLogic,
      ({
        _SynthRangeRef range,
        SynthSubModuleInstantiation inst,
        List<SynthAssignment> inputAssignments,
      })> _fullPackedSwizzleSourceRanges(
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
  ) {
    final ranges = <SynthLogic,
        ({
      _SynthRangeRef range,
      SynthSubModuleInstantiation inst,
      List<SynthAssignment> inputAssignments,
    })>{};

    for (final instantiation in subModuleInstantiations) {
      final module = instantiation.module;
      if (module is! Swizzle || module.isNet) {
        continue;
      }

      final output = instantiation.outputMapping[module.resultSignalName];
      if (output == null) {
        continue;
      }

      final indexedInputs = <({int index, SynthLogic signal})>[];
      final inputAssignments = <SynthAssignment>[];
      var hasUnindexedInput = false;
      for (final entry in instantiation.inputMapping.entries) {
        final index = _swizzleInputIndex(entry.key);
        if (index == null) {
          hasUnindexedInput = true;
          break;
        }
        final inputDriver = _singleFullWidthAssignment(
          entry.value.resolved,
          assignmentsByDestination,
        );
        if (inputDriver != null) {
          inputAssignments.add(inputDriver);
        }
        indexedInputs.add((
          index: index,
          signal: inputDriver?.src.resolved ?? entry.value.resolved,
        ));
      }
      if (hasUnindexedInput || indexedInputs.isEmpty) {
        continue;
      }

      indexedInputs.sort((a, b) => a.index.compareTo(b.index));
      SynthLogic? parentArray;
      var allInputsMatch = true;
      for (final (expectedIndex, input) in indexedInputs.indexed) {
        if (input.index != expectedIndex ||
            input.signal is! SynthLogicArrayElement) {
          allInputsMatch = false;
          break;
        }

        final element = input.signal as SynthLogicArrayElement;
        final array = element.parentArray.resolved;
        parentArray ??= array;
        if (array != parentArray ||
            !_canUsePackedRangeBase(array) ||
            element.logic.arrayIndex != expectedIndex) {
          allInputsMatch = false;
          break;
        }
      }

      if (!allInputsMatch || parentArray == null) {
        continue;
      }

      final arrayLogic = parentArray.logics.first;
      if (arrayLogic is! LogicArray ||
          indexedInputs.length != arrayLogic.elements.length) {
        continue;
      }

      ranges[output.resolved] = (
        range: _SynthRangeRef(parentArray, 0, indexedInputs.length - 1),
        inst: instantiation,
        inputAssignments: inputAssignments,
      );
    }

    return ranges;
  }

  int? _swizzleInputIndex(String portName) {
    final match = RegExp(r'in(\d+)$').firstMatch(portName);
    return match == null ? null : int.parse(match.group(1)!);
  }

  bool _isRangeChainIntermediate(
    SynthLogic intermediate, {
    SynthSubModuleInstantiation? allowedInstantiation,
  }) {
    if (!internalSignals.contains(intermediate) ||
        intermediate.isNet ||
        intermediate.isConstant ||
        !intermediate.isClearable ||
        intermediate.isPort(module) ||
        intermediate.isStructPortElement(module)) {
      return false;
    }

    for (final instantiation in subModuleInstantiations) {
      if (instantiation == allowedInstantiation) {
        continue;
      }
      final mappedSignals = [
        ...instantiation.inputMapping.values,
        ...instantiation.outputMapping.values,
        ...instantiation.inOutMapping.values,
      ];
      if (mappedSignals.any((signal) =>
          signal.resolved == intermediate ||
          (signal is SynthLogicArrayElement &&
              signal.parentArray.resolved == intermediate))) {
        return false;
      }
    }

    final logic = intermediate.logics.firstOrNull;
    return logic is! LogicArray || logic.numUnpackedDimensions == 0;
  }

  bool _isGeneratedSubsetIntermediateCandidate(SynthLogic intermediate) {
    if (!internalSignals.contains(intermediate) ||
        !intermediate.isClearable ||
        intermediate.isPort(module) ||
        intermediate.isStructPortElement(module) ||
        !_canUsePackedRangeBase(intermediate)) {
      return false;
    }

    final arrayLogic = intermediate.logics.singleOrNull;
    return arrayLogic is LogicArray && arrayLogic.naming == Naming.unnamed;
  }

  bool _hasInternalFullWidthSwizzleConsumer(
    SynthLogic swizzleOutput,
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySourceBase,
  ) {
    final consumers = assignmentsBySourceBase[swizzleOutput] ?? const [];
    return consumers.any((assignment) {
      if (assignment is PartialSynthAssignment ||
          assignment.width != swizzleOutput.width) {
        return false;
      }

      final dst = assignment.dst.resolved;
      if (!internalSignals.contains(dst) ||
          dst.isNet ||
          dst.isConstant ||
          dst.isPort(module) ||
          dst.isStructPortElement(module) ||
          dst.logics.any((logic) => logic.isArrayMember) ||
          dst.width != swizzleOutput.width) {
        return false;
      }

      return dst.logics.singleOrNull is! LogicArray;
    });
  }

  _SynthRangeRef _assignmentSourceRange(SynthAssignment assignment) {
    if (assignment is RangeSynthAssignment) {
      return _SynthRangeRef(
        assignment.src.resolved,
        assignment.srcLowerIndex,
        assignment.srcUpperIndex,
      );
    }

    return _SynthRangeRef(
      assignment.src.resolved,
      0,
      assignment.src.width - 1,
    );
  }

  _SynthRangeRef _assignmentDestinationRange(SynthAssignment assignment) {
    if (assignment is PartialSynthAssignment) {
      return _SynthRangeRef(
        assignment.dst.resolved,
        assignment.dstLowerIndex,
        assignment.dstUpperIndex,
      );
    }

    return _SynthRangeRef(
      assignment.dst.resolved,
      0,
      assignment.dst.width - 1,
    );
  }

  SynthLogic _referenceBase(SynthLogic signal) =>
      signal is SynthLogicArrayElement
          ? signal.parentArray.resolved
          : signal.resolved;

  /// Collapses assignments that don't need to remain present.
  void _collapseAssignments() {
    // there might be more assign statements than necessary, so let's ditch them
    var prevAssignmentCount = 0;

    // grab the partial assignments since they can't be merged
    final partialAssignments =
        assignments.whereType<PartialSynthAssignment>().toList();
    assignments.removeWhere((e) => e is PartialSynthAssignment);

    while (prevAssignmentCount != assignments.length) {
      // keep looping until it stops shrinking
      final reducedAssignments = <SynthAssignment>[];
      for (final assignment in CombinedIterableView([
        // we look at non-constant assignments first to maximize merging in case
        // some constant merge scenario is disallowed by a module (e.g. subset)
        assignments.where((a) => !a.src.isConstant && !a.dst.isConstant),
        assignments.where((a) => a.src.isConstant || a.dst.isConstant),
      ])) {
        assert(
          assignment is! PartialSynthAssignment,
          'Partial assignments should have been removed before this.',
        );

        final dst = assignment.dst;
        final src = assignment.src;

        if (src == dst && src.isConstant) {
          // looks like this assignment does nothing -- some sort of circular
          // constant assignment, can just remove it

          continue;
        }

        assert(
          dst != src,
          'No circular assignment allowed between $dst and $src.',
        );

        final mergeResults = SynthLogic.tryMerge(dst, src);

        if (mergeResults != null) {
          final (removed: mergedAway, kept: kept) = mergeResults;

          _applyAssignmentMergeUpdates(mergedAway: mergedAway, kept: kept);
        } else if (assignment.src.isFloatingConstant) {
          internalSignals.remove(assignment.src);
        } else {
          reducedAssignments.add(assignment);
        }
      }
      prevAssignmentCount = assignments.length;
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }

    // add back all the partial assignments that were removed since they could
    // not be merged
    assignments.addAll(partialAssignments);

    // update the look-up table post-merge
    logicToSynthMap.clear();
    for (final synthLogic in [
      ...inputs,
      ...outputs,
      ...inOuts,
      ...internalSignals,
    ]) {
      for (final logic in synthLogic.logics) {
        logicToSynthMap[logic] = synthLogic;
      }
    }
  }

  /// Performs updates to this definition after merging away a signal as part of
  /// [_collapseAssignments].
  void _applyAssignmentMergeUpdates({
    required SynthLogic mergedAway,
    required SynthLogic kept,
  }) {
    final foundInternal = internalSignals.remove(mergedAway);

    if (!foundInternal) {
      final foundKept = internalSignals.remove(kept);
      assert(
        foundKept,
        'One of the two should be internal since we cant merge ports.',
      );

      if (inputs.contains(mergedAway)) {
        inputs
          ..remove(mergedAway)
          ..add(kept);
      } else if (outputs.contains(mergedAway)) {
        outputs
          ..remove(mergedAway)
          ..add(kept);
      } else if (inOuts.contains(mergedAway)) {
        inOuts
          ..remove(mergedAway)
          ..add(kept);
      }
    }

    if (mergedAway.isArray) {
      for (final (keptElementIndex, keptElementLogic)
          in (kept.logics.first as LogicArray).elements.indexed) {
        // should be safe to just check the first logic's elements since they
        // should all be the same synth, and arrays only merge with arrays
        final keptElement = getSynthLogic(keptElementLogic)!;
        final mergedAwayElement = getSynthLogic(
          (mergedAway.logics.first as LogicArray).elements[keptElementIndex],
        )!;

        if (keptElement == mergedAwayElement) {
          continue;
        }

        keptElement.adopt(mergedAwayElement, force: true);

        _applyAssignmentMergeUpdates(
          mergedAway: mergedAwayElement,
          kept: keptElement,
        );
      }
    }
  }
}
