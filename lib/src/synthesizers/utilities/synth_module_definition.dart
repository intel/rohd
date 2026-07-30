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

  /// Creates a range reference if the bounds are valid for [base].
  static _SynthRangeRef? tryCreate(SynthLogic base, int lower, int upper) {
    if (lower < 0 || upper < lower || upper >= base.width) {
      return null;
    }
    return _SynthRangeRef(base, lower, upper);
  }

  /// Whether [other] is fully contained in this range.
  bool contains(_SynthRangeRef other) =>
      base == other.base && other.lower >= lower && other.upper <= upper;
}

/// Submodule users indexed both by an exact mapped signal and by the mapped
/// signal's array reference base.
typedef _SubmoduleSignalUseIndex = ({
  Map<SynthLogic, Set<SynthSubModuleInstantiation>> exact,
  Map<SynthLogic, Set<SynthSubModuleInstantiation>> byReferenceBase,
});

/// Yields maximal contiguous runs in [sortedItems] according to
/// [continuesRun].
Iterable<({int start, int end})> _contiguousRuns<T>(
  List<T> sortedItems,
  bool Function(T previous, T current) continuesRun,
) sync* {
  if (sortedItems.isEmpty) {
    return;
  }

  var start = 0;
  for (var index = 1; index < sortedItems.length; index++) {
    if (!continuesRun(sortedItems[index - 1], sortedItems[index])) {
      yield (start: start, end: index - 1);
      start = index;
    }
  }
  yield (start: start, end: sortedItems.length - 1);
}

/// Groups [assignments] by the key selected by [keyOf].
Map<K, List<SynthAssignment>> _assignmentsBy<K>(
  Iterable<SynthAssignment> assignments,
  K Function(SynthAssignment assignment) keyOf,
) {
  final assignmentsByKey = <K, List<SynthAssignment>>{};
  for (final assignment in assignments) {
    assignmentsByKey.putIfAbsent(keyOf(assignment), () => []).add(assignment);
  }
  return assignmentsByKey;
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
  /// Submodules that should claim names after emitted objects.
  final Set<SynthSubModuleInstantiation> _weakNameClaimSubmodules = {};

  /// Signals that should claim names after emitted objects.
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
        final newReceiverConst = getSynthLogic(Const(
          receiver.value,
          preferredRadix: receiver.preferredRadix,
        ))!;
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
    _collapseConstantBackedRangeIntermediates();
    _collapseAssignments();
    _assignSubmodulePortMapping();

    _pruneUnused();
    _collapseConstantBackedRangeIntermediates();
    _pruneUnused();
    _pruneClearedSubsetConstantSources();

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

    final collapseCandidates = inlineableSubmoduleInstantiations.where(
      (subModuleInstantiation) {
        final resultSynthLogic = _inlineResultLogic(subModuleInstantiation);

        return resultSynthLogic != null &&
            singleUseSignals.contains(resultSynthLogic) &&
            subModuleInstantiation.needsInstantiation;
      },
    ).toList();

    // Keep every module in an inline dependency cycle materialized so that
    // rendering expressions cannot recurse through the cycle indefinitely.
    final candidateByResult = <SynthLogic, SynthSubModuleInstantiation>{
      for (final candidate in collapseCandidates)
        _inlineResultLogic(candidate)!.resolved: candidate,
    };
    final visited = <SynthSubModuleInstantiation>{};
    final activeIndices = <SynthSubModuleInstantiation, int>{};
    final activePath = <SynthSubModuleInstantiation>[];
    final cyclicCandidates = <SynthSubModuleInstantiation>{};

    void findCycles(SynthSubModuleInstantiation candidate) {
      visited.add(candidate);
      activeIndices[candidate] = activePath.length;
      activePath.add(candidate);

      final resultSignalName =
          (candidate.module as InlineSystemVerilog).resultSignalName;
      for (final input in <SynthLogic>[
        ...candidate.inputMapping.values,
        ...candidate.inOutMapping.entries
            .where((entry) => entry.key != resultSignalName)
            .map((entry) => entry.value),
      ]) {
        final dependency = candidateByResult[input.resolved];
        if (dependency == null) {
          continue;
        }

        final cycleStart = activeIndices[dependency];
        if (cycleStart != null) {
          cyclicCandidates.addAll(activePath.skip(cycleStart));
        } else if (!visited.contains(dependency)) {
          findCycles(dependency);
        }
      }

      activePath.removeLast();
      activeIndices.remove(candidate);
    }

    for (final candidate in collapseCandidates) {
      if (!visited.contains(candidate)) {
        findCycles(candidate);
      }
    }

    return collapseCandidates
        .where((candidate) => !cyclicCandidates.contains(candidate));
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

      final assignmentConnectedSubmoduleMappingSignals =
          _assignmentConnectedSubmoduleMappingSignals();
      final sharedSubmoduleMappingSignals = _sharedSubmoduleMappingSignals();

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

        if (assignmentConnectedSubmoduleMappingSignals
                .contains(internalSignal.resolved) ||
            sharedSubmoduleMappingSignals.contains(internalSignal.resolved)) {
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
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);

    for (final submoduleInstantiation in subModuleInstantiations) {
      for (final inputName in submoduleInstantiation.module.inputs.keys) {
        final orig = submoduleInstantiation.inputMapping[inputName]!;
        submoduleInstantiation.setInputMapping(
          inputName,
          _resolvedSubmoduleInputMapping(orig, assignmentsByDestination),
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

  /// Resolves a submodule input mapping through any replacement and, when the
  /// mapped signal is fully driven by a packed scalar assignment, through that
  /// driver as well.
  SynthLogic _resolvedSubmoduleInputMapping(
    SynthLogic mappedSignal,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
  ) {
    final resolved = mappedSignal.replacement ?? mappedSignal;
    return _fullWidthInputMappingSource(resolved, assignmentsByDestination) ??
        resolved;
  }

  /// Returns the source of a single full-width scalar [RangeSynthAssignment]
  /// into [mappedSignal], or `null` when the mapped signal must remain named.
  SynthLogic? _fullWidthInputMappingSource(
    SynthLogic mappedSignal,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination,
  ) {
    final drivers = assignmentsByDestination[mappedSignal.resolved];
    if (drivers == null || drivers.length != 1) {
      return null;
    }

    final driver = drivers.single;
    if (driver is! RangeSynthAssignment) {
      return null;
    }

    final sourceRange = _assignmentSourceRange(driver);
    final destinationRange = _assignmentDestinationRange(driver);
    if (destinationRange.base != mappedSignal.resolved ||
        destinationRange.lower != 0 ||
        destinationRange.upper != mappedSignal.width - 1 ||
        sourceRange.width != mappedSignal.width ||
        sourceRange.lower != 0 ||
        sourceRange.upper != sourceRange.base.width - 1 ||
        sourceRange.base.isArray) {
      return null;
    }

    return sourceRange.base;
  }

  /// Finds submodule mapping signals that participate in scalar or packed range
  /// assignments across a submodule boundary and therefore must not be pruned
  /// before rendering.
  Set<SynthLogic> _assignmentConnectedSubmoduleMappingSignals() {
    final submoduleInputMappingReferences =
        _submoduleMappingReferences(includeInputs: true, includeOutputs: false);
    final submoduleOutputMappingReferences =
        _submoduleMappingReferences(includeInputs: false, includeOutputs: true);
    final assignmentConnectedSignals = <SynthLogic>{};

    var foundInlineDependency = true;
    while (foundInlineDependency) {
      foundInlineDependency = false;
      for (final instantiation in subModuleInstantiations) {
        final inlineModule = instantiation.module;
        if (inlineModule is! BusSubset || inlineModule.original.isNet) {
          continue;
        }
        final mappedOutputs = [
          ...instantiation.outputMapping.values,
          ...instantiation.inOutMapping.values,
        ];
        if (!mappedOutputs.any(
          (mapped) => _isPackedBitArrayElement(mapped.resolved),
        )) {
          continue;
        }
        final outputReferences = {
          for (final mapped in mappedOutputs) mapped.resolved,
          for (final mapped in mappedOutputs) _referenceBase(mapped.resolved),
        };
        if (outputReferences
            .every((ref) => !submoduleInputMappingReferences.contains(ref))) {
          continue;
        }
        for (final mapped in [
          ...instantiation.inputMapping.values,
          ...instantiation.inOutMapping.values,
        ]) {
          final resolved = mapped.resolved;
          foundInlineDependency |=
              submoduleInputMappingReferences.add(resolved);
          foundInlineDependency |=
              submoduleInputMappingReferences.add(_referenceBase(resolved));
        }
      }
    }

    for (final assignment in assignments) {
      final sourceRange = _assignmentSourceRange(assignment);
      final destinationRange = _assignmentDestinationRange(assignment);

      final sourceBase = sourceRange.base.resolved;
      final destinationBase = destinationRange.base.resolved;
      final destinationReferenceBase = _referenceBase(destinationBase);
      final sourceIsMappedOutput =
          submoduleOutputMappingReferences.contains(sourceBase);

      if (submoduleInputMappingReferences.contains(destinationBase) &&
          sourceIsMappedOutput) {
        assignmentConnectedSignals.add(destinationBase);
      } else if (submoduleInputMappingReferences.contains(destinationBase) &&
          !destinationReferenceBase.isArray &&
          !sourceBase.isArray) {
        assignmentConnectedSignals.add(destinationBase);
      }
      if (sourceIsMappedOutput) {
        assignmentConnectedSignals.add(sourceBase);
      }
    }

    return assignmentConnectedSignals;
  }

  /// Finds signals that are used by multiple active submodule port mappings.
  /// After full assignment merging, these shared mapping signals may be the
  /// only remaining evidence that a parent-level wire is still required.
  Set<SynthLogic> _sharedSubmoduleMappingSignals() {
    final inputMappingUseCounts = <SynthLogic, int>{};
    final outputMappingUseCounts = <SynthLogic, int>{};
    final inOutMappingUseCounts = <SynthLogic, int>{};

    void addReferences(Map<SynthLogic, int> useCounts, SynthLogic signal) {
      final resolved = signal.resolved;
      for (final reference in {resolved, _referenceBase(resolved)}) {
        useCounts.update(
          reference,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    for (final submoduleInstantiation in subModuleInstantiations) {
      if (!submoduleInstantiation.needsInstantiation ||
          submoduleInstantiation.module is InlineSystemVerilog) {
        continue;
      }

      for (final signal in submoduleInstantiation.inputMapping.values) {
        addReferences(inputMappingUseCounts, signal);
      }
      for (final signal in submoduleInstantiation.outputMapping.values) {
        addReferences(outputMappingUseCounts, signal);
      }
      for (final signal in submoduleInstantiation.inOutMapping.values) {
        addReferences(inOutMappingUseCounts, signal);
      }
    }

    final mappingReferences = {
      ...inputMappingUseCounts.keys,
      ...outputMappingUseCounts.keys,
      ...inOutMappingUseCounts.keys,
    };

    final sharedMappingSignals = <SynthLogic>{};
    for (final reference in mappingReferences) {
      final inputUses = inputMappingUseCounts[reference] ?? 0;
      final outputUses = outputMappingUseCounts[reference] ?? 0;
      final inOutUses = inOutMappingUseCounts[reference] ?? 0;

      if ((inputUses > 0 && outputUses > 0) ||
          (inOutUses > 0 && (inputUses > 0 || outputUses > 0)) ||
          inOutUses > 1) {
        sharedMappingSignals.add(reference);
      }
    }

    return sharedMappingSignals;
  }

  /// Collects active submodule mapping signals plus their reference bases, so
  /// array elements and aggregate mappings compare consistently.
  Set<SynthLogic> _submoduleMappingReferences({
    required bool includeInputs,
    required bool includeOutputs,
  }) {
    final mappedReferences = <SynthLogic>{};

    for (final submoduleInstantiation in subModuleInstantiations) {
      if (!submoduleInstantiation.needsInstantiation ||
          submoduleInstantiation.module is InlineSystemVerilog) {
        continue;
      }

      final mappedSignals = [
        if (includeInputs) ...submoduleInstantiation.inputMapping.values,
        if (includeOutputs) ...submoduleInstantiation.outputMapping.values,
        ...submoduleInstantiation.inOutMapping.values,
      ];
      for (final mappedSignal in mappedSignals) {
        final resolved = mappedSignal.resolved;
        mappedReferences
          ..add(resolved)
          ..add(_referenceBase(resolved));
      }
    }

    return mappedReferences;
  }

  /// Indexes every submodule port mapping by its exact signal and, for array
  /// elements, by the direct parent array used for aggregate comparisons.
  _SubmoduleSignalUseIndex _submoduleSignalUseIndex() {
    final exact = <SynthLogic, Set<SynthSubModuleInstantiation>>{};
    final byReferenceBase = <SynthLogic, Set<SynthSubModuleInstantiation>>{};
    for (final instantiation in subModuleInstantiations) {
      for (final mappedSignal in {
        ...instantiation.inputMapping.values,
        ...instantiation.outputMapping.values,
        ...instantiation.inOutMapping.values,
      }) {
        final resolved = mappedSignal.resolved;
        exact.putIfAbsent(resolved, () => {}).add(instantiation);
        byReferenceBase
            .putIfAbsent(_referenceBase(resolved), () => {})
            .add(instantiation);
      }
    }
    return (exact: exact, byReferenceBase: byReferenceBase);
  }

  /// Whether [signal] is an element of a one-dimensional packed bit array.
  bool _isPackedBitArrayElement(SynthLogic signal) {
    if (signal is! SynthLogicArrayElement) {
      return false;
    }
    final parentLogic = signal.parentArray.resolved.logics.singleOrNull;
    return parentLogic is LogicArray &&
        parentLogic.dimensions.length == 1 &&
        parentLogic.elementWidth == 1 &&
        parentLogic.numUnpackedDimensions == 0;
  }

  /// Signal names are selected through [Namer.signalNameOfBest] or kept as
  /// literal constants. Submodule names are selected through
  /// [Namer.instanceNameOf]. All non-constant names share a single namespace
  /// managed by the module's [Namer].
  void _pickNames() {
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

      for (final run in _contiguousRuns(
        group,
        (previous, current) =>
            dstIndex(current) == dstIndex(previous) + 1 &&
            srcIndex(current) == srcIndex(previous) + 1,
      )) {
        addRun(group, run.start, run.end);
      }
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

  /// Width-oriented collapse of bit-blasted assignments into packed ranges.
  ///
  /// This pass looks for individual one-bit assignments that are really pieces
  /// of the same packed connection. For example, a sequence like
  /// `dst[1] <= src[13]`, `dst[2] <= src[14]`, ... can become one
  /// `dst[4:1] <= src[16:13]` [RangeSynthAssignment]. Sources may be direct
  /// array elements or temporary [BusSubset] outputs; temporary outputs are
  /// traced back to the original packed base before grouping.
  ///
  /// Candidates are grouped by source base, destination base, and constant
  /// index offset. A group is then split into contiguous runs, so the pass
  /// grows assignments in width without composing through arbitrary depth.
  /// Depth composition through intermediates is handled by
  /// [_collapseChainedRangeAssignments].
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
    final assignmentsBySourceBase = _assignmentsBy(
        assignments, (assignment) => _referenceBase(assignment.src));
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
    final assignmentsBySource =
        _assignmentsBy(assignments, (assignment) => assignment.src.resolved);
    final submoduleSignalUses = _submoduleSignalUseIndex();
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
      // A candidate is one bit of a future cross-object range assignment:
      // `dstBase[dstBit] <= srcBase[srcBit]`. The bases must be different;
      // this pass is packing plumbing between objects, not proving that an
      // overlapping intra-object move like `a[4:1] <= a[16:13]` is safe.
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
          !_canUsePackedRangeSource(resolvedSrc.range.base) ||
          !_canUsePackedRangeBase(dst.base)) {
        reducedAssignments.add(assignment);
        continue;
      }

      // Keep only assignments that share a stable bit offset. Each group can
      // later become a packed range assignment such as
      // `dstBase[4:1] <= srcBase[16:13]`.
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

    // Generated `assignSubset` arrays need full-coverage accounting. If only
    // part of such an array is collapsed away, the remaining helper can change
    // undriven/floating behavior. A fully covered helper can be replaced as a
    // single range safely; partial helpers stay conservative unless they are
    // known generated intermediates with live sources.
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

      for (final run in _contiguousRuns(
        group,
        (previous, current) =>
            current.dst.lower == previous.dst.lower + 1 &&
            current.src.lower == previous.src.lower + 1,
      )) {
        changed |= _addSimpleRangeRun(
          reducedAssignments,
          group,
          run.start,
          run.end,
          assignmentsBySource,
          generatedSubsetCandidates,
          generatedSubsetIntermediates,
          fullyCoveredGeneratedSubsets,
          submoduleSignalUses,
        );
      }
    }

    if (changed) {
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }

  /// Whether every assignment consuming [base] feeds a [Swizzle] input.
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

  /// Adds one contiguous run from [_collapseSimpleRangeAssignments].
  ///
  /// Single-bit runs are left alone because there is no width to recover. Wider
  /// runs become [RangeSynthAssignment]s. When the source bits came from a
  /// temporary [BusSubset], the temporary module and signal are cleared only if
  /// every remaining use is covered by the assignments being replaced.
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
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySource,
    Set<SynthLogic> generatedSubsetCandidates,
    Set<SynthLogic> generatedSubsetIntermediates,
    Set<SynthLogic> fullyCoveredGeneratedSubsets,
    _SubmoduleSignalUseIndex submoduleSignalUses,
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

    // Selecting a range directly from a literal is not legal SystemVerilog.
    // A run that covers the whole constant instead becomes a partial
    // destination assignment, such as `dst[6:4] = 3'h0`.
    reducedAssignments.add(first.src.base.isConstant &&
            first.src.lower == 0 &&
            last.src.upper == first.src.base.width - 1
        ? PartialSynthAssignment(
            first.src.base,
            first.dst.base,
            dstUpperIndex: last.dst.upper,
            dstLowerIndex: first.dst.lower,
          )
        : RangeSynthAssignment(
            first.src.base,
            first.dst.base,
            srcUpperIndex: last.src.upper,
            srcLowerIndex: first.src.lower,
            dstUpperIndex: last.dst.upper,
            dstLowerIndex: first.dst.lower,
          ));
    final replacedAssignments = {
      for (var index = start; index <= end; index++) group[index].assignment,
    };
    for (var index = start; index <= end; index++) {
      final sourceSignal = group[index].sourceSignal?.resolved;
      final sourceSubmodule = group[index].sourceSubmodule;
      if (sourceSignal != null &&
          sourceSubmodule != null &&
          _canClearReplacedSourceSignal(
            sourceSignal,
            assignmentsBySource,
            replacedAssignments,
            submoduleSignalUses: submoduleSignalUses,
            allowedInstantiation: sourceSubmodule,
          )) {
        sourceSubmodule.clearInstantiation();
        sourceSignal.clearDeclaration();
      }
    }
    return true;
  }

  /// Whether a replaced temporary source has no assignment or submodule users
  /// outside [replacedAssignments] and [allowedInstantiation].
  bool _canClearReplacedSourceSignal(
    SynthLogic sourceSignal,
    Map<SynthLogic, List<SynthAssignment>> assignmentsBySource,
    Set<SynthAssignment> replacedAssignments, {
    required _SubmoduleSignalUseIndex submoduleSignalUses,
    required SynthSubModuleInstantiation allowedInstantiation,
  }) {
    final assignmentUsers = assignmentsBySource[sourceSignal] ?? const [];
    return assignmentUsers.every(replacedAssignments.contains) &&
        !_hasSubmoduleSignalUse(
          sourceSignal,
          submoduleSignalUses,
          allowedInstantiation: allowedInstantiation,
        );
  }

  /// Whether [signal] is mapped by an instantiation other than
  /// [allowedInstantiation].
  bool _hasSubmoduleSignalUse(
    SynthLogic signal,
    _SubmoduleSignalUseIndex submoduleSignalUses, {
    required SynthSubModuleInstantiation allowedInstantiation,
  }) {
    final resolved = signal.resolved;
    final users = <SynthSubModuleInstantiation>{
      ...?submoduleSignalUses.exact[resolved],
      ...?submoduleSignalUses.byReferenceBase[resolved],
      ...?submoduleSignalUses.exact[_referenceBase(resolved)],
    };
    return users.any((instantiation) => instantiation != allowedInstantiation);
  }

  /// Whether [sourceBase] remains meaningful when only part of a generated
  /// subset helper is collapsed.
  bool _canPartiallyCollapseGeneratedSubsetSource(SynthLogic sourceBase) =>
      (sourceBase.isConstant && !sourceBase.isFloatingConstant) ||
      _isLiveRangeSource(sourceBase);

  /// Whether [source] resolves through full-width drivers to a constant.
  ///
  /// [visiting] prevents cycles in malformed or bidirectional connection
  /// graphs from recursing indefinitely.
  bool _isConstantBackedSource(
    SynthLogic source,
    Map<SynthLogic, List<SynthAssignment>> assignmentsByDestination, [
    Set<SynthLogic> visiting = const {},
  ]) {
    if (source.isConstant) {
      return true;
    }
    if (visiting.contains(source)) {
      return false;
    }

    final driver = _singleFullWidthAssignment(
      source,
      assignmentsByDestination,
    );
    return driver != null &&
        _isConstantBackedSource(
          _assignmentSourceRange(driver).base,
          assignmentsByDestination,
          {...visiting, source},
        );
  }

  /// Whether [sourceBase] has a live identity or connection outside disposable
  /// range intermediates.
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

    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
    final assignmentsBySource =
        _assignmentsBy(assignments, (assignment) => assignment.src.resolved);
    final submoduleSignalUses = _submoduleSignalUseIndex();
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
      if (dst.width <= 1 || dst.logics.any((logic) => logic is LogicArray)) {
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
          !_isLiveRangeSource(src.base) ||
          (internalSignals.contains(src.base) && src.base.isClearable) ||
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
      if (_canClearReplacedSourceSignal(
        assignment.src.resolved,
        assignmentsBySource,
        {assignment},
        submoduleSignalUses: submoduleSignalUses,
        allowedInstantiation: busSubsetRange.inst,
      )) {
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

  /// Maps each usable non-net [BusSubset] output to its packed source range and
  /// helper instantiation, resolving through full-width temporary drivers.
  Map<SynthLogic, ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>
      _busSubsetSourceRanges() {
    final directRanges = <SynthLogic,
        ({_SynthRangeRef range, SynthSubModuleInstantiation inst})>{};
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);

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
          !_canUsePackedRangeSource(original.resolved)) {
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
      if (!_canUsePackedRangeSource(resolvedRange.base)) {
        continue;
      }

      ranges[entry.key] = (range: resolvedRange, inst: entry.value.inst);
    }
    return ranges;
  }

  /// Resolves [range] through full-width assignments and known [BusSubset]
  /// ranges while preserving its relative bit offsets.
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

    return _SynthRangeRef.tryCreate(
          sourceRange.base,
          sourceRange.lower + range.lower,
          sourceRange.lower + range.upper,
        ) ??
        range;
  }

  /// Returns the source range of [signal]'s sole full-width driver.
  ///
  /// Known [BusSubset] sources are recursively resolved, with [visiting]
  /// preventing cycles.
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

  /// Returns [signal]'s only assignment when it covers the full destination.
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

  /// Resolves the packed source represented by an array-element assignment or
  /// a temporary [BusSubset] output.
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

  /// Returns the packed destination range for an array-element assignment.
  _SynthRangeRef? _simpleAssignmentDestinationRange(
          SynthAssignment assignment) =>
      _arrayElementRange(assignment.dst.resolved);

  /// Returns the one-bit packed range represented by [signal], when its parent
  /// array has a supported packed layout.
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

  /// Whether [base] can be referenced by packed indices in a backend-neutral
  /// range assignment.
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

  /// Constants can be regrouped after named constant subsets are bit-blasted,
  /// but floating constants must retain their undriven semantics.
  bool _canUsePackedRangeSource(SynthLogic base) =>
      (base.isConstant && !base.isFloatingConstant) ||
      _canUsePackedRangeBase(base);

  /// Depth-oriented composition of range assignments through an intermediate.
  ///
  /// Unlike [_collapseSimpleRangeAssignments], this pass does not try to find
  /// more adjacent bits. It looks for a single producer and a single consumer
  /// around an internal helper and composes their ranges, for example
  /// `mid[3:0] <= src[7:4]` plus `dst[1:0] <= mid[3:2]` becoming
  /// `dst[1:0] <= src[7:6]`.
  void _collapseChainedRangeAssignments() {
    final generatedSubsetIntermediates = _generatedSubsetIntermediates();
    final mappedIntermediates = <SynthLogic>{};
    for (final instantiation in subModuleInstantiations) {
      for (final mapped in {
        ...instantiation.inputMapping.values,
        ...instantiation.outputMapping.values,
        ...instantiation.inOutMapping.values,
      }) {
        mappedIntermediates.add(mapped.resolved);
        if (mapped is SynthLogicArrayElement) {
          mappedIntermediates.add(mapped.parentArray.resolved);
        }
      }
    }
    final activeAssignments = LinkedHashSet<SynthAssignment>.of(assignments);
    final assignmentsByDestination = <SynthLogic, Set<SynthAssignment>>{};
    final assignmentsBySource = <SynthLogic, Set<SynthAssignment>>{};

    /// Adds [assignment] to both mutable chain indexes.
    void addToIndexes(SynthAssignment assignment) {
      assignmentsByDestination
          .putIfAbsent(_referenceBase(assignment.dst), () => {})
          .add(assignment);
      assignmentsBySource
          .putIfAbsent(_referenceBase(assignment.src), () => {})
          .add(assignment);
    }

    /// Removes [assignment] from both mutable chain indexes.
    void removeFromIndexes(SynthAssignment assignment) {
      assignmentsByDestination[_referenceBase(assignment.dst)]
          ?.remove(assignment);
      assignmentsBySource[_referenceBase(assignment.src)]?.remove(assignment);
    }

    assignments.forEach(addToIndexes);
    final workQueue = ListQueue<PartialSynthAssignment>.from(
      assignments.whereType<PartialSynthAssignment>(),
    );

    while (workQueue.isNotEmpty) {
      final producer = workQueue.removeFirst();
      if (!activeAssignments.contains(producer)) {
        continue;
      }

      final intermediate = producer.dst.resolved;
      final producers = assignmentsByDestination[intermediate];
      final consumers = assignmentsBySource[intermediate];
      if (producers?.length != 1 ||
          consumers?.length != 1 ||
          producers!.single != producer) {
        continue;
      }

      final consumer = consumers!.single;
      final replacement = _composeChainedRangeAssignment(
        producer: producer,
        consumer: consumer,
        intermediate: intermediate,
        generatedSubsetIntermediates: generatedSubsetIntermediates,
        mappedIntermediates: mappedIntermediates,
      );
      if (replacement == null) {
        continue;
      }

      activeAssignments
        ..remove(producer)
        ..remove(consumer);
      removeFromIndexes(producer);
      removeFromIndexes(consumer);
      activeAssignments.add(replacement);
      addToIndexes(replacement);
      workQueue.add(replacement);
      intermediate.clearDeclaration();
    }

    assignments
      ..clear()
      ..addAll(activeAssignments);
  }

  /// Composes [producer] and [consumer] through [intermediate].
  ///
  /// The selected intermediate ranges must contain one another so their
  /// offsets can be translated without changing width or overlap semantics.
  /// Generated `assignSubset` intermediates additionally allow a producer to
  /// replace part of a wider consumer because their complete coverage is
  /// validated by the generated-subset analysis.
  RangeSynthAssignment? _composeChainedRangeAssignment({
    required PartialSynthAssignment producer,
    required SynthAssignment consumer,
    required SynthLogic intermediate,
    required Set<SynthLogic> generatedSubsetIntermediates,
    required Set<SynthLogic> mappedIntermediates,
  }) {
    if (!_isRangeChainIntermediate(
      intermediate,
      mappedIntermediates: mappedIntermediates,
    )) {
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
      final sourceRange = _SynthRangeRef.tryCreate(
        producerSrc.base,
        sourceLower,
        sourceUpper,
      );
      if (sourceRange == null) {
        return null;
      }
      replacementSrc = sourceRange;
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
      final destinationRange = _SynthRangeRef.tryCreate(
        consumerDst.base,
        dstLower,
        dstUpper,
      );
      if (destinationRange == null) {
        return null;
      }
      replacementSrc = producerSrc;
      replacementDst = destinationRange;
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

  /// Replaces a named constant intermediate with its literal at each range
  /// consumer.
  ///
  /// For example, `tie = 3'h0` plus `bus[6:4] = tie` becomes
  /// `bus[6:4] = 3'h0`. The intermediate is removed only when every consumer
  /// was replaced, so fanout and unsupported uses remain conservative.
  void _collapseConstantBackedRangeIntermediates() {
    final mappedSignals = _submoduleMappingReferences(
      includeInputs: true,
      includeOutputs: true,
    );
    while (true) {
      final assignmentsByDestination =
          _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
      final assignmentsBySource =
          _assignmentsBy(assignments, (assignment) => assignment.src.resolved);
      final claimedAssignments = <SynthAssignment>{};
      final replacements = <SynthAssignment, PartialSynthAssignment>{};
      final removedProducers = <SynthAssignment>{};
      final clearedIntermediates = <SynthLogic>{};

      for (final intermediate in internalSignals.toList()) {
        final producers = assignmentsByDestination[intermediate.resolved];
        final consumers = assignmentsBySource[intermediate.resolved];
        if (producers?.length != 1 ||
            consumers == null ||
            consumers.isEmpty ||
            intermediate.hasPreservedName ||
            mappedSignals.contains(intermediate.resolved)) {
          continue;
        }

        final producer = producers!.single;
        if (claimedAssignments.contains(producer)) {
          continue;
        }
        if (intermediate.width == 0 ||
            producer.src.width == 0 ||
            producer.dst.width == 0) {
          continue;
        }
        final producerSrc = _assignmentSourceRange(producer);
        final producerDst = _assignmentDestinationRange(producer);
        if (!producerSrc.base.isConstant ||
            producerSrc.base.isFloatingConstant ||
            producerSrc.lower != 0 ||
            producerSrc.upper != producerSrc.base.width - 1 ||
            producerDst.base != intermediate.resolved ||
            producerDst.lower != 0 ||
            producerDst.upper != intermediate.width - 1) {
          continue;
        }

        final intermediateReplacements =
            <SynthAssignment, PartialSynthAssignment>{};
        for (final consumer in consumers) {
          if (consumer is! PartialSynthAssignment ||
              claimedAssignments.contains(consumer)) {
            continue;
          }
          final consumerSrc = _assignmentSourceRange(consumer);
          final consumerDst = _assignmentDestinationRange(consumer);
          final feedsArraySubset =
              (assignmentsBySource[consumerDst.base.resolved] ?? const [])
                  .any((downstream) => downstream.dst.dstConnections.any(
                        (destination) => destination.isArrayMember,
                      ));
          if (consumerSrc.base != intermediate.resolved ||
              _referenceBase(consumerDst.base).isArray ||
              feedsArraySubset ||
              consumerSrc.lower != 0 ||
              consumerSrc.upper != intermediate.width - 1 ||
              consumerDst.width != producerSrc.width) {
            continue;
          }
          intermediateReplacements[consumer] = PartialSynthAssignment(
            producerSrc.base,
            consumerDst.base,
            dstUpperIndex: consumerDst.upper,
            dstLowerIndex: consumerDst.lower,
          );
        }
        if (intermediateReplacements.isEmpty) {
          continue;
        }

        replacements.addAll(intermediateReplacements);
        claimedAssignments.addAll(intermediateReplacements.keys);
        if (intermediateReplacements.length == consumers.length) {
          claimedAssignments.add(producer);
          removedProducers.add(producer);
          clearedIntermediates.add(intermediate);
        }
      }

      if (replacements.isEmpty) {
        break;
      }

      final updatedAssignments = [
        for (final assignment in assignments)
          if (replacements.containsKey(assignment))
            replacements[assignment]!
          else if (!removedProducers.contains(assignment))
            assignment,
      ];
      assignments
        ..clear()
        ..addAll(updatedAssignments);
      for (final intermediate in clearedIntermediates) {
        intermediate.clearDeclaration();
      }
      internalSignals.removeAll(clearedIntermediates);
    }
  }

  /// Drops constant-backed signals referenced only by cleared [BusSubset]
  /// helpers.
  ///
  /// Active packed-array mappings and current-module array ports are excluded
  /// because their elements can still depend on a constant after ordinary
  /// assignment pruning.
  void _pruneClearedSubsetConstantSources() {
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
    final assignmentsBySource =
        _assignmentsBy(assignments, (assignment) => assignment.src.resolved);
    final mappedInstantiationsBySignal =
        <SynthLogic, Set<SynthSubModuleInstantiation>>{};
    for (final instantiation in subModuleInstantiations) {
      for (final mapped in {
        ...instantiation.inputMapping.values,
        ...instantiation.outputMapping.values,
        ...instantiation.inOutMapping.values,
      }) {
        mappedInstantiationsBySignal
            .putIfAbsent(mapped.resolved, () => {})
            .add(instantiation);
      }
    }

    final protectedArrayBases = {
      for (final port in [...inputs, ...outputs, ...inOuts])
        if (_referenceBase(port.resolved).isArray) _arrayRoot(port.resolved),
      for (final instantiation in subModuleInstantiations)
        if (instantiation.needsInstantiation)
          for (final mapped in instantiation.inputMapping.values)
            if (_referenceBase(mapped.resolved).isArray)
              _arrayRoot(mapped.resolved),
    };
    final removedAssignments = <SynthAssignment>{};
    final removedSignals = <SynthLogic>{};
    for (final signal in internalSignals.toList()) {
      final producers = assignmentsByDestination[signal.resolved] ?? const [];
      final consumers = assignmentsBySource[signal.resolved] ?? const [];
      final constantBacked = signal.isConstant ||
          (producers.isNotEmpty &&
              producers.every(
                (producer) => producer.src.resolved.isConstant,
              ));
      if (!constantBacked ||
          signal.hasPreservedName ||
          consumers.isNotEmpty ||
          (signal is SynthLogicArrayElement &&
              protectedArrayBases.contains(_arrayRoot(signal))) ||
          signal.dstConnections.any((destination) {
            final synthDestination = getSynthLogic(destination)?.resolved;
            return synthDestination != null &&
                protectedArrayBases.contains(
                  _arrayRoot(synthDestination),
                );
          })) {
        continue;
      }

      final mappedInstantiations =
          mappedInstantiationsBySignal[signal.resolved] ?? const {};
      final feedsProtectedArray = mappedInstantiations.any(
        (instantiation) =>
            !instantiation.needsInstantiation &&
            instantiation.module is BusSubset &&
            instantiation.inputMapping.values.any(
              (mapped) => mapped.resolved == signal.resolved,
            ) &&
            instantiation.outputMapping.values.any(
              (mapped) => protectedArrayBases.contains(_arrayRoot(mapped)),
            ),
      );
      if (feedsProtectedArray) {
        continue;
      }
      if (mappedInstantiations.isEmpty ||
          mappedInstantiations.every(
            (instantiation) =>
                !instantiation.needsInstantiation &&
                instantiation.module is BusSubset,
          )) {
        removedAssignments.addAll(producers);
        removedSignals.add(signal);
      }
    }

    if (removedAssignments.isNotEmpty) {
      final retainedAssignments = [
        for (final assignment in assignments)
          if (!removedAssignments.contains(assignment)) assignment,
      ];
      assignments
        ..clear()
        ..addAll(retainedAssignments);
    }
    for (final signal in removedSignals) {
      signal.clearDeclaration();
    }
    internalSignals.removeAll(removedSignals);
  }

  /// Collapses generated `assignSubset` helpers feeding packed swizzles.
  ///
  /// `Logic.assignSubset` builds a temporary array and then swizzles that array
  /// back into a packed value. When every producer bit for that helper is
  /// accounted for, the helper and swizzle can be replaced with direct packed
  /// range assignments to the swizzle output. This is a specialized helper
  /// pass: it requires full coverage so partially driven helpers keep their
  /// original undriven/floating behavior.
  void _collapseGeneratedSubsetSwizzleRangeAssignments() {
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
    final assignmentsBySourceBase = _assignmentsBy(
        assignments, (assignment) => _referenceBase(assignment.src));

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

    final assignmentsByBaseDestination = _assignmentsBy(
        assignments, (assignment) => _referenceBase(assignment.dst));
    final assignmentsBySource = _assignmentsBy(
        assignments, (assignment) => _referenceBase(assignment.src));
    final submoduleSignalUses = _submoduleSignalUseIndex();
    final realOutputMappingsBySignal = <SynthLogic,
        List<
            ({
              SynthSubModuleInstantiation instantiation,
              String portName,
            })>>{};
    for (final instantiation in subModuleInstantiations) {
      if (!instantiation.needsInstantiation ||
          instantiation.module is InlineSystemVerilog) {
        continue;
      }
      for (final entry in instantiation.outputMapping.entries) {
        realOutputMappingsBySignal
            .putIfAbsent(entry.value.resolved, () => [])
            .add((instantiation: instantiation, portName: entry.key));
      }
    }
    final knownSourceRanges = {
      for (final entry in _busSubsetSourceRanges().entries)
        entry.key: entry.value.range,
    };

    final replacements = <SynthAssignment, SynthAssignment>{};
    final consumedAssignments = <SynthAssignment>{};
    final outputMappingReplacements = <({
      SynthSubModuleInstantiation instantiation,
      String portName,
      SynthLogicPackedBitReference reference,
    })>[];
    for (final entry in swizzlesByBase.entries) {
      final intermediate = entry.key;
      final swizzles = entry.value;
      final swizzle = swizzles.singleOrNull;
      final sourceUsers = assignmentsBySource[intermediate] ?? const [];
      final producers = assignmentsByBaseDestination[intermediate];
      if (swizzles.length != 1 ||
          swizzle == null ||
          producers == null ||
          producers.isEmpty ||
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
      final mappedProducerAssignments = <SynthAssignment>{};
      final producerOutputMappingReplacements = <({
        SynthSubModuleInstantiation instantiation,
        String portName,
        SynthLogicPackedBitReference reference,
      })>[];
      final resolvedProducerSources = {
        for (final producer in producers)
          producer: _resolveKnownRangeThroughFullWidthDrivers(
            _assignmentSourceRange(producer),
            assignmentsByDestination,
            knownSourceRanges,
          ),
      };
      final commonSourceBase = resolvedProducerSources.values
          .map((source) => source.base)
          .toSet()
        ..removeWhere((source) => !source.isArray);
      final packedArraySource = commonSourceBase.singleOrNull;
      final coveredPackedArrayBits = <int>{};
      var preservesWholePackedArray =
          packedArraySource != null && packedArraySource.width == output.width;
      if (preservesWholePackedArray) {
        for (final producer in producers) {
          final source = resolvedProducerSources[producer]!;
          final destination = _assignmentDestinationRange(producer);
          if (source.base != packedArraySource ||
              destination.base != intermediate ||
              source.width != destination.width ||
              !swizzle.range.contains(destination) ||
              source.lower != destination.lower - swizzle.range.lower) {
            preservesWholePackedArray = false;
            break;
          }
          for (var bit = source.lower; bit <= source.upper; bit++) {
            if (!coveredPackedArrayBits.add(bit)) {
              preservesWholePackedArray = false;
              break;
            }
          }
          if (!preservesWholePackedArray) {
            break;
          }
        }
      }
      if (preservesWholePackedArray &&
          coveredPackedArrayBits.length == output.width) {
        // Keep complete ordered packed arrays on the existing swizzle path,
        // which renders the array's packed selection without an unnecessary
        // destination selection.
        continue;
      }
      final hasConstantProducer = resolvedProducerSources.values.any(
        (source) => _isConstantBackedSource(
          source.base,
          assignmentsByDestination,
        ),
      );
      final realMappedOutputProducerCount = producers
          .where((producer) =>
              realOutputMappingsBySignal[producer.src.resolved]?.isNotEmpty ??
              false)
          .length;
      final seenDestinationBits = <int>{};
      var canReplaceAll = true;
      for (final producer in producers) {
        final producerSrc = resolvedProducerSources[producer]!;
        final producerDst = _assignmentDestinationRange(producer);
        if (producerDst.base != intermediate ||
            !swizzle.range.contains(producerDst) ||
            producerSrc.base == output ||
            producerSrc.base.isNet ||
            (producerSrc.base.isConstant &&
                (producerSrc.lower != 0 ||
                    producerSrc.upper != producerSrc.base.width - 1))) {
          canReplaceAll = false;
          break;
        }
        if (!producerSrc.base.isConstant &&
            !_isLiveRangeSource(producerSrc.base)) {
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

        final outputMappings =
            realOutputMappingsBySignal[producer.src.resolved] ?? const [];
        final producerSourceUsers =
            assignmentsBySource[producer.src.resolved] ?? const [];
        final canMapDirectly = realMappedOutputProducerCount == 1 &&
            (!hasConstantProducer ||
                producerDst.lower == 0 ||
                producerDst.upper == intermediate.width - 1);
        if (canMapDirectly &&
            outputMappings.length == 1 &&
            producerSourceUsers.length == 1 &&
            producerSourceUsers.single == producer &&
            producerSrc.width == 1 &&
            producerDst.width == 1 &&
            !_hasSubmoduleSignalUse(
              producer.src.resolved,
              submoduleSignalUses,
              allowedInstantiation: outputMappings.single.instantiation,
            )) {
          final packedReference = SynthLogicPackedBitReference(
            output,
            dstLower,
            parentSynthModuleDefinition: this,
          );
          producerOutputMappingReplacements.add((
            instantiation: outputMappings.single.instantiation,
            portName: outputMappings.single.portName,
            reference: packedReference,
          ));
          mappedProducerAssignments.add(producer);
        } else {
          producerReplacements[producer] =
              producerSrc.base.width == 1 || producerSrc.base.isConstant
                  ? PartialSynthAssignment(
                      producerSrc.base,
                      output,
                      dstUpperIndex: dstUpper,
                      dstLowerIndex: dstLower,
                    )
                  : RangeSynthAssignment(
                      producerSrc.base,
                      output,
                      srcUpperIndex: producerSrc.upper,
                      srcLowerIndex: producerSrc.lower,
                      dstUpperIndex: dstUpper,
                      dstLowerIndex: dstLower,
                    );
        }
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
      consumedAssignments
        ..addAll(swizzle.inputAssignments)
        ..addAll(mappedProducerAssignments);
      outputMappingReplacements.addAll(producerOutputMappingReplacements);
      intermediate.clearDeclaration();
      swizzle.inst.clearInstantiation();
    }

    if (replacements.isNotEmpty || outputMappingReplacements.isNotEmpty) {
      for (final replacement in outputMappingReplacements) {
        replacement.instantiation.setOutputMapping(
          replacement.portName,
          replacement.reference,
          replace: true,
        );
      }
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

  /// Whether [source] drives any array member assignment.
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

  /// Resolves [range] through clearable full-width drivers and
  /// [knownSourceRanges], retaining the original relative selection.
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

    return _SynthRangeRef.tryCreate(
          resolvedSourceRange.base,
          resolvedSourceRange.lower + range.lower,
          resolvedSourceRange.lower + range.upper,
        ) ??
        range;
  }

  /// Finds unnamed generated-subset candidates and the subset intermediates
  /// that feed a live full-width swizzle consumer.
  ({Set<SynthLogic> candidates, Set<SynthLogic> intermediates})
      _generatedSubsetIntermediateSets() {
    final assignmentsByDestination =
        _assignmentsBy(assignments, (assignment) => assignment.dst.resolved);
    final assignmentsBySourceBase = _assignmentsBy(
        assignments, (assignment) => _referenceBase(assignment.src));

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

  /// Finds generated subset intermediates eligible for range composition.
  Set<SynthLogic> _generatedSubsetIntermediates() =>
      _generatedSubsetIntermediateSets().intermediates;

  /// Filters [swizzleSourceRanges] to generated subset intermediates with a
  /// live full-width internal consumer.
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

  /// Maps each non-net [Swizzle] output that reconstructs a complete packed
  /// array to its source range, helper, and any full-width input assignments.
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

  /// Parses the numeric index from a [Swizzle] input named `inN`.
  int? _swizzleInputIndex(String portName) {
    final match = RegExp(r'in(\d+)$').firstMatch(portName);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// Whether [intermediate] is a disposable non-net signal that can be removed
  /// from a range chain without crossing a port or unpacked-array boundary.
  bool _isRangeChainIntermediate(
    SynthLogic intermediate, {
    SynthSubModuleInstantiation? allowedInstantiation,
    Set<SynthLogic>? mappedIntermediates,
  }) {
    if (!internalSignals.contains(intermediate) ||
        intermediate.isNet ||
        intermediate.isConstant ||
        !intermediate.isClearable ||
        intermediate.isPort(module) ||
        intermediate.isStructPortElement(module)) {
      return false;
    }

    if (mappedIntermediates?.contains(intermediate) ?? false) {
      return false;
    }

    for (final instantiation in mappedIntermediates == null
        ? subModuleInstantiations
        : const <SynthSubModuleInstantiation>[]) {
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

  /// Whether [intermediate] has the unnamed packed-array shape generated by
  /// `assignSubset`.
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

  /// Whether [swizzleOutput] feeds a full-width disposable internal signal.
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

  /// Returns the packed source range represented by [assignment].
  _SynthRangeRef _assignmentSourceRange(SynthAssignment assignment) {
    if (assignment is RangeSynthAssignment) {
      return _SynthRangeRef(
        assignment.src.resolved,
        assignment.srcLowerIndex,
        assignment.srcUpperIndex,
      );
    }

    final arrayElementRange = _arrayElementRange(assignment.src.resolved);
    if (arrayElementRange != null) {
      return arrayElementRange;
    }

    return _SynthRangeRef(
      assignment.src.resolved,
      0,
      assignment.src.width - 1,
    );
  }

  /// Returns the packed destination range represented by [assignment].
  _SynthRangeRef _assignmentDestinationRange(SynthAssignment assignment) {
    if (assignment is PartialSynthAssignment) {
      return _SynthRangeRef(
        assignment.dst.resolved,
        assignment.dstLowerIndex,
        assignment.dstUpperIndex,
      );
    }

    final arrayElementRange = _arrayElementRange(assignment.dst.resolved);
    if (arrayElementRange != null) {
      return arrayElementRange;
    }

    return _SynthRangeRef(
      assignment.dst.resolved,
      0,
      assignment.dst.width - 1,
    );
  }

  /// Returns the packed object referenced by [signal] for grouping and usage
  /// comparisons.
  SynthLogic _referenceBase(SynthLogic signal) => switch (signal) {
        SynthLogicArrayElement() => signal.parentArray.resolved,
        SynthLogicPackedBitReference() => signal.packedBase.resolved,
        _ => signal.resolved,
      };

  /// Returns the outermost array containing [signal], or [signal] itself when
  /// it is not an array element.
  SynthLogic _arrayRoot(SynthLogic signal) {
    var root = signal.resolved;
    while (root is SynthLogicArrayElement) {
      root = root.parentArray.resolved;
    }
    return root;
  }

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
