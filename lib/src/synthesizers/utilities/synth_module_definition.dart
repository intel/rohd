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
import 'package:rohd/src/synthesizers/utilities/synth_enum_definition.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

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
  final Uniquifier _synthIdentifierUniquifier;

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

        newSynth = SynthLogic(
          logic,
          namingOverride: (logic.isPort && logic.parentModule != module)
              ? Naming.mergeable
              : null,
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

  /// Creates a new definition representation for this [module].
  SynthModuleDefinition(this.module)
      : _synthIdentifierUniquifier = Uniquifier(
          reservedNames: {
            ...module.inputs.keys,
            ...module.outputs.keys,
            ...module.inOuts.keys,
          },
        ) {
    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values)
      ..addAll(module.inOuts.values);

    for (final output in module.outputs.values) {
      outputs.add(_getSynthLogic(output)!);
    }

    // make sure disconnected inputs are included
    for (final input in module.inputs.values) {
      inputs.add(_getSynthLogic(input)!);
    }

    // make sure disconnected inouts are included, also
    for (final inOut in module.inOuts.values) {
      inOuts.add(_getSynthLogic(inOut)!);
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

      if (receiver is LogicArray) {
        logicsToTraverse.addAll(receiver.elements);
      }

      if (receiver.isArrayMember) {
        logicsToTraverse.add(receiver.parentStructure!);
      }

      final synthReceiver = _getSynthLogic(receiver)!;

      if (receiver is LogicNet) {
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

      final receiverIsModuleInput =
          module.isInput(receiver) && !receiver.isArrayMember;
      final receiverIsModuleOutput =
          module.isOutput(receiver) && !receiver.isArrayMember;
      final receiverIsModuleInOut =
          module.isInOut(receiver) && !receiver.isArrayMember;

      final synthDriver = _getSynthLogic(driver);

      if (receiverIsModuleInput) {
        inputs.add(synthReceiver);
      } else if (receiverIsModuleOutput) {
        outputs.add(synthReceiver);
      } else if (receiverIsModuleInOut) {
        inOuts.add(synthReceiver);
      } else {
        internalSignals.add(synthReceiver);
      }

      final receiverIsSubmoduleInOut =
          receiver.isInOut && (receiver.parentModule?.parent == module);
      if (receiverIsSubmoduleInOut) {
        final subModule = receiver.parentModule!;

        if (synthReceiver is! SynthLogicArrayElement) {
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
        if (synthReceiver is! SynthLogicArrayElement) {
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
        if (synthReceiver is! SynthLogicArrayElement) {
          getSynthSubModuleInstantiation(subModule)
              .setInputMapping(receiver.name, synthReceiver);
        }
      }
    }

    // The order of these is important!
    _collapseArrays();
    _collapseAssignments();
    _assignSubmodulePortMapping();
    _adjustTypePairs();
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

  void _adjustTypePairs() {
    for (final submoduleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      submoduleInstantiation.adjustTypePairs();
    }
  }

  final Map<SynthEnumDefinitionKey, SynthEnumDefinition> _enumDefinitions =
      <SynthEnumDefinitionKey, SynthEnumDefinition>{};

  List<SynthEnumDefinition> get enumDefinitions =>
      _enumDefinitions.values.toList(growable: false);

  void _pickDefinitionEnumName(SynthLogic synthEnum) {
    assert(synthEnum.isEnum, 'Only call this on SynthLogic that is an enum.');
    final key = SynthEnumDefinitionKey(synthEnum.characteristicEnum!);
    if (_enumDefinitions.containsKey(key)) {
      // already have a definition for this enum
      synthEnum.enumDefinition = _enumDefinitions[key];
    } else {
      // create a new definition for this enum
      final newDefinition = SynthEnumDefinition(
        synthEnum.characteristicEnum!,
        _synthIdentifierUniquifier,
      );
      _enumDefinitions[key] = newDefinition;
      synthEnum.enumDefinition = newDefinition;
    }
  }

  /// Picks names of signals and sub-modules.
  void _pickNames() {
    // first ports get priority
    for (final input in inputs) {
      input.pickName(_synthIdentifierUniquifier);
    }
    for (final output in outputs) {
      output.pickName(_synthIdentifierUniquifier);
    }
    for (final inOut in inOuts) {
      inOut.pickName(_synthIdentifierUniquifier);
    }

    // pick names of *reserved* definition-type enums
    final nonReservedEnumDefs = <SynthLogic>[];
    for (final signal in internalSignals.where((e) => e.isEnum)) {
      if (signal.characteristicEnum!.reserveDefinitionName) {
        _pickDefinitionEnumName(signal);
      } else {
        nonReservedEnumDefs.add(signal);
      }
    }

    // pick names of *reserved* submodule instances
    final nonReservedSubmodules = <SynthSubModuleInstantiation>[];
    for (final submodule in moduleToSubModuleInstantiationMap.values) {
      if (submodule.module.reserveName) {
        submodule.pickName(_synthIdentifierUniquifier);
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
        signal.pickName(_synthIdentifierUniquifier);
      } else {
        nonReservedSignals.add(signal);
      }
    }

    // then enum definitions that are not reserved
    nonReservedEnumDefs.forEach(_pickDefinitionEnumName);

    // then submodule instances
    for (final submodule
        in nonReservedSubmodules.where((element) => element.needsDeclaration)) {
      submodule.pickName(_synthIdentifierUniquifier);
    }

    // then the rest of the internal signals
    for (final signal in nonReservedSignals) {
      signal.pickName(_synthIdentifierUniquifier);
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

    while (prevAssignmentCount != assignments.length) {
      // keep looping until it stops shrinking
      final reducedAssignments = <SynthAssignment>[];
      for (final assignment in assignments) {
        final dst = assignment.dst;
        final src = assignment.src;

        assert(dst != src,
            'No circular assignment allowed between $dst and $src.');

        final mergedAway = SynthLogic.tryMerge(dst, src);

        if (mergedAway != null) {
          final kept = mergedAway == dst ? src : dst;

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
