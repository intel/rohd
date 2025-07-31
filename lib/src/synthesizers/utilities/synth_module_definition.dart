// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_module_definition.dart
// Definitions for a module definition
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// A version of [BusSubset] that can be used for slicing on [LogicStructure]
/// ports.
class _BusSubsetForStructSlice extends BusSubset {
  /// Creates a [BusSubset] for use in [SynthModuleDefinition]s during
  /// [LogicStructure] port slicing.
  _BusSubsetForStructSlice(super.bus, super.startIndex, super.endIndex);

  // we override this since it's added post-build
  @override
  bool get hasBuilt => true;
}

/// Represents the definition of a module.
class SynthModuleDefinition {
  /// The [Module] being defined.
  final Module module;

  /// All the assignments that are part of this definition.
  final List<SynthAssignment> assignments = [];

  /// All other internal signals that are not ports.
  ///
  /// This is the only collection that maye have mergeable items in it.
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

  /// Used to uniquify any identifiers, including signal names
  /// and module instances.
  final Uniquifier _synthInstantiationNameUniquifier;

  /// Either accesses a previously created [SynthLogic] corresponding to
  /// [logic], or else creates a new one and adds it to the [logicToSynthMap].
  SynthLogic? _getSynthLogic(
    Logic? logic,
  ) {
    if (logic == null) {
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      SynthLogic newSynth;
      if (logic.isArrayMember) {
        // grab the parent array (potentially recursively)
        final parentArraySynthLogic =
            // ignore: unnecessary_null_checks
            _getSynthLogic(logic.parentStructure!);

        newSynth = SynthLogicArrayElement(logic, parentArraySynthLogic!);
      } else {
        final disallowConstName = logic.isInput &&
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
          namingOverride: namingOverride,
          constNameDisallowed: disallowConstName,
        );
      }

      logicToSynthMap[logic] = newSynth;
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

    final portSynth = _getSynthLogic(port)!;

    var idx = 0;
    for (final leafElement in port.leafElements) {
      final leafSynth = _getSynthLogic(leafElement)!;
      internalSignals.add(leafSynth);
      assignments.add(PartialSynthAssignment(leafSynth, portSynth,
          dstUpperIndex: idx + leafElement.width - 1, dstLowerIndex: idx));
      idx += leafElement.width;
    }
  }

  /// Drives all leaf elements of [port] using a (modified) [BusSubset].
  ///
  /// This is intended for use when receiving from an input of a module from
  /// within the module, or for receiving the output of a sub-module.
  @protected
  void _subsetReceiveStructPort(LogicStructure port) {
    final portSynth = _getSynthLogic(port)!;

    var idx = 0;
    for (final leafElement in port.leafElements) {
      final leafSynth = _getSynthLogic(leafElement)!;
      internalSignals.add(leafSynth);

      // this is DISCONNECTED, just a module used for synthesizing
      final subsetMod = _BusSubsetForStructSlice(
        (port.isNet ? LogicNet.new : Logic.new)(
            width: port.width, name: 'DUMMY'),
        idx,
        idx + leafElement.width - 1,
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
      : _synthInstantiationNameUniquifier = Uniquifier(
          reservedNames: {
            ...module.inputs.keys,
            ...module.outputs.keys,
            ...module.inOuts.keys,
          },
        ),
        assert(
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
      final outputSynth = _getSynthLogic(output)!;
      outputs.add(outputSynth);

      if (output is LogicStructure && output is! LogicArray) {
        _partialAssignStructPort(output);
      }
    }

    // make sure disconnected inputs are included
    for (final input in module.inputs.values) {
      final inputSynth = _getSynthLogic(input)!;
      inputs.add(inputSynth);

      if (input is LogicStructure && input is! LogicArray) {
        _subsetReceiveStructPort(input);
      }
    }

    // make sure disconnected inouts are included, also
    for (final inOut in module.inOuts.values) {
      inOuts.add(_getSynthLogic(inOut)!);

      if (inOut is LogicStructure && inOut is! LogicArray) {
        // for nets, we can just use the normal bus subset here in either
        // direction!
        _subsetReceiveStructPort(inOut);
      }
    }

    // find any named signals sitting around that don't do anything
    // this is not necessary for functionality, just nice naming inclusion
    logicsToTraverse.addAll(
      module.internalSignals
          .where((element) => element.naming != Naming.unnamed),
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
          ' but $receiver was not.');

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

      final synthReceiver = _getSynthLogic(receiver)!;

      if (receiver is LogicNet) {
        // only for the leaves, that's why only `LogicNet` and not array/struct

        logicsToTraverse.addAll([
          ...receiver.srcConnections,
          ...receiver.dstConnections
        ].where((element) => element.parentModule == module));

        for (final srcConnection in receiver.srcConnections) {
          if (srcConnection.parentModule == module ||
              (srcConnection.isOutput &&
                  srcConnection.parentModule!.parent == module)) {
            final netSynthDriver = _getSynthLogic(srcConnection)!;

            assignments.add(SynthAssignment(
              netSynthDriver,
              synthReceiver,
            ));
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

      final synthDriver = _getSynthLogic(driver);

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
            'Internal signals should not be ports also.');
        internalSignals.add(synthReceiver);
      }

      final receiverIsSubmoduleInOut =
          receiver.isInOut && (receiver.parentModule?.parent == module);
      if (receiverIsSubmoduleInOut) {
        final subModule = receiver.parentModule!;

        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement) {
          getSynthSubModuleInstantiation(subModule)
              .setInOutMapping(receiver.name, synthReceiver);
        }

        logicsToTraverse.addAll(subModule.inOuts.values);
      }

      final receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleOutput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement) {
          getSynthSubModuleInstantiation(subModule)
              .setOutputMapping(receiver.name, synthReceiver);
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
        final newReceiverConst = _getSynthLogic(Const(receiver.value))!;
        internalSignals.add(newReceiverConst);
        assignments.add(SynthAssignment(newReceiverConst, synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! SynthLogicArrayElement &&
            !synthReceiver.isStructPortElement) {
          getSynthSubModuleInstantiation(subModule)
              .setInputMapping(receiver.name, synthReceiver);
        }
      }
    }

    // The order of these is important!
    _collapseArrays();
    _collapseAssignments();
    _assignSubmodulePortMapping();
    process();
    _pickNames();
  }

  /// Performs additional processing on the current definition to simplify,
  /// reduce, etc.
  @protected
  @visibleForOverriding
  void process() {
    // by default, nothing!
  }

  /// Updates all sub-module instantiations with information about which
  /// [SynthLogic] should be used for their ports.
  void _assignSubmodulePortMapping() {
    for (final submoduleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final inputName in submoduleInstantiation.module.inputs.keys) {
        final orig = submoduleInstantiation.inputMapping[inputName]!;
        submoduleInstantiation.setInputMapping(
            inputName, orig.replacement ?? orig,
            replace: true);
      }

      for (final outputName in submoduleInstantiation.module.outputs.keys) {
        final orig = submoduleInstantiation.outputMapping[outputName]!;
        submoduleInstantiation.setOutputMapping(
            outputName, orig.replacement ?? orig,
            replace: true);
      }

      for (final inOutName in submoduleInstantiation.module.inOuts.keys) {
        final orig = submoduleInstantiation.inOutMapping[inOutName]!;
        submoduleInstantiation.setInOutMapping(
            inOutName, orig.replacement ?? orig,
            replace: true);
      }
    }
  }

  /// Picks names of signals and sub-modules.
  void _pickNames() {
    // first ports get priority
    for (final input in inputs) {
      input.pickName(_synthInstantiationNameUniquifier);
    }
    for (final output in outputs) {
      output.pickName(_synthInstantiationNameUniquifier);
    }
    for (final inOut in inOuts) {
      inOut.pickName(_synthInstantiationNameUniquifier);
    }

    // pick names of *reserved* submodule instances
    final nonReservedSubmodules = <SynthSubModuleInstantiation>[];
    for (final submodule in moduleToSubModuleInstantiationMap.values) {
      if (submodule.module.reserveName) {
        submodule.pickName(_synthInstantiationNameUniquifier);
        assert(submodule.module.name == submodule.name,
            'Expect reserved names to retain their name.');
      } else {
        nonReservedSubmodules.add(submodule);
      }
    }

    // then *reserved* internal signals get priority
    final nonReservedSignals = <SynthLogic>[];
    for (final signal in internalSignals) {
      if (signal.isReserved) {
        signal.pickName(_synthInstantiationNameUniquifier);
      } else {
        nonReservedSignals.add(signal);
      }
    }

    // then submodule instances
    for (final submodule
        in nonReservedSubmodules.where((element) => element.needsDeclaration)) {
      submodule.pickName(_synthInstantiationNameUniquifier);
    }

    // then the rest of the internal signals
    for (final signal in nonReservedSignals) {
      signal.pickName(_synthInstantiationNameUniquifier);
    }
  }

  /// Merges bit blasted array assignments into one single assignment when
  /// it's full array-full array assignment
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
          final srcArray = src.parentArray;
          final dstArray = dst.parentArray;

          assert(srcArray.logics.length == 1, 'should be 1 name for the array');
          assert(dstArray.logics.length == 1, 'should be 1 name for the array');

          if (srcArray.logics.first.elements.length !=
                  dstArray.logics.first.elements.length ||
              boringArrayPairs.contains((srcArray, dstArray))) {
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
        assert(
            srcArray.logics.first.elements.length ==
                dstArray.logics.first.elements.length,
            'should be equal lengths of elements in both arrays by now');

        // first requirement is that all elements have been assigned
        var shouldMerge =
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
          reducedAssignments.addAll(arrAssignments);
          boringArrayPairs.add((srcArray, dstArray));
        }
      }

      prevAssignmentCount = assignments.length;
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
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
      for (final assignment in assignments) {
        assert(assignment is! PartialSynthAssignment,
            'Partial assignments should have been removed before this.');

        final dst = assignment.dst;
        final src = assignment.src;

        assert(dst != src,
            'No circular assignment allowed between $dst and $src.');

        final mergeResults = SynthLogic.tryMerge(dst, src);

        if (mergeResults != null) {
          final (removed: mergedAway, kept: kept) = mergeResults;

          final foundInternal = internalSignals.remove(mergedAway);
          if (!foundInternal) {
            final foundKept = internalSignals.remove(kept);
            assert(foundKept,
                'One of the two should be internal since we cant merge ports.');

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
      ...internalSignals
    ]) {
      for (final logic in synthLogic.logics) {
        logicToSynthMap[logic] = synthLogic;
      }
    }
  }
}
