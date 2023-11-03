// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog.dart
// Definition for SystemVerilog Synthesizer
//
// 2021 August 26
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

//TODO: can we sort inputs/outputs based on declaration order instead of alphabetical?

/// A [Synthesizer] which generates equivalent SystemVerilog as the
/// given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible.
class SystemVerilogSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) => module is! CustomSystemVerilog;

  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name
  /// [instanceName].
  ///
  /// [inputs] and [outputs] map `module` input/output name to a verilog signal name.
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [inputs] and [outputs] should be:
  /// inputs:  `{ 'a' : 'sig_a', 'b' : 'sig_b'}`
  /// outputs: `{ 'c' : 'sig_c' }`
  static String instantiationVerilogWithParameters(
      Module module,
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      {Map<String, String>? parameters,
      bool forceStandardInstantiation = false}) {
    if (!forceStandardInstantiation) {
      if (module is CustomSystemVerilog) {
        return module.instantiationVerilog(
            instanceType, instanceName, inputs, outputs);
      }
    }

    //non-custom needs more details
    final connections = <String>[];

    // ignore: invalid_use_of_protected_member
    for (final signalName in module.inputs.keys) {
      connections.add('.$signalName(${inputs[signalName]})');
    }

    for (final signalName in module.outputs.keys) {
      connections.add('.$signalName(${outputs[signalName]})');
    }

    final connectionsStr = connections.join(',');
    var parameterString = '';
    if (parameters != null) {
      final parameterContents =
          parameters.entries.map((e) => '.${e.key}(${e.value})').join(',');
      parameterString = '#($parameterContents)';
    }
    return '$instanceType $parameterString $instanceName($connectionsStr);';
  }

  @override
  SynthesisResult synthesize(
          Module module, Map<Module, String> moduleToInstanceTypeMap) =>
      _SystemVerilogSynthesisResult(module, moduleToInstanceTypeMap);
}

/// Allows a [Module] to define a custom implementation of SystemVerilog to be
/// injected in generated output instead of instantiating a separate `module`.
mixin CustomSystemVerilog on Module {
  /// Generates custom SystemVerilog to be injected in place of a `module`
  /// instantiation.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively of the module that would have been instantiated had it not
  /// been overridden.  The [Map]s [inputs] and [outputs] are a mapping from the
  /// [Module]'s port names to the names of the signals that are passed into
  /// those ports in the generated SystemVerilog.
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs);

  /// A list of names of [input]s which should not have any SystemVerilog
  /// expressions (including constants) in-lined into them. Only signal names
  /// will be fed into these.
  @protected
  final List<String> expressionlessInputs = const [];
}

/// Allows a [Module] to define a special type of [CustomSystemVerilog] which
/// can be inlined within other SystemVerilog code.
///
/// The inline SystemVerilog will get parentheses wrapped around it and
/// then dropped into other code in the same way a variable name is.
mixin InlineSystemVerilog on Module implements CustomSystemVerilog {
  /// Generates custom SystemVerilog to be injected in place of the output
  /// port's corresponding signal name.
  ///
  /// The [inputs] are a mapping from the [Module]'s port names to the names of
  /// the signals that are passed into those ports in the generated
  /// SystemVerilog.
  ///
  /// The output will be appropriately wrapped with parentheses to guarantee
  /// proper order of operations.
  String inlineVerilog(Map<String, String> inputs);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (outputs.length != 1) {
      throw Exception(
          'Inline verilog must have exactly one output, but saw $outputs.');
    }
    final output = outputs.values.first;
    final inline = inlineVerilog(inputs);
    return 'assign $output = $inline;  // $instanceName';
  }

  @override
  @protected
  final List<String> expressionlessInputs = const [];
}

/// A [SynthesisResult] representing a conversion of a [Module] to
/// SystemVerilog.
class _SystemVerilogSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports
  late final String _portsString;

  /// A cached copy of the generated contents of the module
  late final String _moduleContentsString;

  final _SynthModuleDefinition _synthModuleDefinition;
  _SystemVerilogSynthesisResult(
      Module module, Map<Module, String> moduleToInstanceTypeMap)
      : _synthModuleDefinition = _SynthModuleDefinition(module),
        super(module, moduleToInstanceTypeMap) {
    _portsString = _verilogPorts();
    _moduleContentsString = _verilogModuleContents(moduleToInstanceTypeMap);
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is _SystemVerilogSynthesisResult &&
      other._portsString == _portsString &&
      other._moduleContentsString == _moduleContentsString;

  @override
  int get matchHashCode =>
      _portsString.hashCode ^ _moduleContentsString.hashCode;

  @override
  String toFileContents() => _toVerilog(moduleToInstanceTypeMap);

  List<String> _verilogInputs() {
    final declarations = _synthModuleDefinition.inputs
        .map((sig) => 'input logic ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  List<String> _verilogOutputs() {
    final declarations = _synthModuleDefinition.outputs
        .map((sig) => 'output logic ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  String _verilogInternalNets() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalNets
        .sorted((a, b) => a.name.compareTo(b.name))) {
      if (sig.needsDeclaration) {
        declarations.add('logic ${sig.definitionName()};');
      }
    }
    return declarations.join('\n');
  }

  String _verilogAssignments() {
    final assignmentLines = <String>[];
    for (final assignment in _synthModuleDefinition.assignments) {
      assignmentLines
          .add('assign ${assignment.dst.name} = ${assignment.src.name};');
    }
    return assignmentLines.join('\n');
  }

  String _verilogSubModuleInstantiations(
      Map<Module, String> moduleToInstanceTypeMap) {
    final subModuleLines = <String>[];
    for (final subModuleInstantiation
        in _synthModuleDefinition.moduleToSubModuleInstantiationMap.values) {
      if (SystemVerilogSynthesizer()
              .generatesDefinition(subModuleInstantiation.module) &&
          !moduleToInstanceTypeMap.containsKey(subModuleInstantiation.module)) {
        throw Exception('No defined instance type found.');
      }
      final instanceType =
          moduleToInstanceTypeMap[subModuleInstantiation.module] ?? '*NONE*';
      final instantiationVerilog =
          subModuleInstantiation.instantiationVerilog(instanceType);
      if (instantiationVerilog != null) {
        subModuleLines.add(instantiationVerilog);
      }
    }
    return subModuleLines.join('\n');
  }

  String _verilogModuleContents(Map<Module, String> moduleToInstanceTypeMap) =>
      [
        _verilogInternalNets(),
        _verilogAssignments(),
        _verilogSubModuleInstantiations(moduleToInstanceTypeMap),
      ].where((element) => element.isNotEmpty).join('\n');

  String _verilogPorts() => [
        ..._verilogInputs(),
        ..._verilogOutputs(),
      ].join(',\n');

  String _toVerilog(Map<Module, String> moduleToInstanceTypeMap) {
    final verilogModuleName = moduleToInstanceTypeMap[module];
    return [
      'module $verilogModuleName(',
      _portsString,
      ');',
      _moduleContentsString,
      'endmodule : $verilogModuleName'
    ].join('\n');
  }
}

/// Represents an instantiation of a module within another module.
class _SynthSubModuleInstantiation {
  final Module module;
  final String name;
  // final Map<_SynthLogic, Logic> inputMapping = {};
  // final Map<_SynthLogic, Logic> outputMapping = {};
  final Map<String, _SynthLogic> inputMapping = {};
  final Map<String, _SynthLogic> outputMapping = {};
  bool _needsDeclaration = true;
  bool get needsDeclaration => _needsDeclaration;
  late final Map<_SynthLogic, _SynthSubModuleInstantiation>
      _synthLogicToInlineableSynthSubmoduleMap;
  _SynthSubModuleInstantiation(this.module, this.name);

  @override
  String toString() =>
      "_SynthSubModuleInstantiation '$name', module name:'${module.name}'";

  void clearDeclaration() {
    _needsDeclaration = false;
  }

  Map<String, String> _moduleInputsMap() =>
      inputMapping.map((name, synthLogic) => MapEntry(
          name,
          _synthLogicToInlineableSynthSubmoduleMap[synthLogic]
                  ?.inlineVerilog() ??
              synthLogic.name));

  String inlineVerilog() =>
      '(${(module as InlineSystemVerilog).inlineVerilog(_moduleInputsMap())})';

  String? instantiationVerilog(String instanceType) {
    if (!needsDeclaration) {
      return null;
    }
    return SystemVerilogSynthesizer.instantiationVerilogWithParameters(
      module,
      instanceType,
      name,
      _moduleInputsMap(),
      outputMapping.map((name, synthLogic) => MapEntry(
          name, // port name guaranteed to match
          synthLogic.name)),
    );
  }
}

/// Represents the definition of a module.
class _SynthModuleDefinition {
  final Module module;

  final List<_SynthAssignment> assignments = [];

  /// All other internal signals that are not ports.
  ///
  /// This is the only collection that maye have mergeable items in it.
  final Set<_SynthLogic> internalNets = {};

  /// All the input ports.
  ///
  /// This will *never* have any mergeable items init.
  final Set<_SynthLogic> inputs = {};

  /// ALl the output ports.
  ///
  /// This will *never* have any mergeable items init.
  final Set<_SynthLogic> outputs = {};

  final Map<Logic, _SynthLogic> logicToSynthMap = {};

  final Map<Module, _SynthSubModuleInstantiation>
      moduleToSubModuleInstantiationMap = {};
  _SynthSubModuleInstantiation _getSynthSubModuleInstantiation(Module m) {
    if (moduleToSubModuleInstantiationMap.containsKey(m)) {
      return moduleToSubModuleInstantiationMap[m]!;
    } else {
      final newSSMI = _SynthSubModuleInstantiation(
          m,
          _getUniqueSynthSubModuleInstantiationName(
              m.uniqueInstanceName, m.reserveName));
      moduleToSubModuleInstantiationMap[m] = newSSMI;
      return newSSMI;
    }
  }

  @override
  String toString() => "module name: '${module.name}'";

  /// Used to uniquify any identifiers, including signal names
  /// and module instances.
  final Uniquifier _synthInstantiationNameUniquifier;

  // String _getUniqueSynthLogicName(String? initialName, bool portName) {
  //   if (portName && initialName == null) {
  //     throw Exception('Port name cannot be null.');
  //   }
  //   return _synthInstantiationNameUniquifier.getUniqueName(
  //       initialName: initialName, reserved: portName);
  // }

  String _getUniqueSynthSubModuleInstantiationName(
          String? initialName, bool reserved) =>
      _synthInstantiationNameUniquifier.getUniqueName(
          initialName: initialName, nullStarter: 'm', reserved: reserved);

  _SynthLogic? _getSynthLogic(
    Logic? logic,
    //  bool allowPortName
  ) {
    if (logic == null) {
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      _SynthLogic newSynth;
      if (logic.isArrayMember) {
        // grab the parent array (potentially recursively)
        final parentArraySynthLogic =
            // ignore: unnecessary_null_checks
            _getSynthLogic(logic.parentStructure!);
        // , allowPortName);

        newSynth = _SynthLogicArrayElement(logic, parentArraySynthLogic!);
      } else {
        // final synthLogicName =
        //     _getUniqueSynthLogicName(logic.name, allowPortName);

        // TODO: name of var and is this good?
        final disallowConstName = logic.isInput &&
            logic.parentModule is CustomSystemVerilog &&
            (logic.parentModule! as CustomSystemVerilog)
                .expressionlessInputs
                .contains(logic.name);

        newSynth = _SynthLogic(
          logic,
          namingOverride: (logic.isPort && logic.parentModule != module)
              // TODO: if this is a non-mergeable port, make it renameable?
              ? Naming.mergeable
              : null,
          // synthLogicName,
          // renameable: !allowPortName,
          constNameDisallowed: disallowConstName,
        );
      }

      logicToSynthMap[logic] = newSynth;
      return newSynth;
    }
  }

  _SynthModuleDefinition(this.module)
      : _synthInstantiationNameUniquifier = Uniquifier(
          reservedNames: {
            // ignore: invalid_use_of_protected_member
            ...module.inputs.keys,
            ...module.outputs.keys,
          },
        ) {
    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values);
    for (final output in module.outputs.values) {
      outputs.add(_getSynthLogic(output)!);
    }

    // make sure disconnected inputs are included
    // ignore: invalid_use_of_protected_member
    for (final input in module.inputs.values) {
      inputs.add(_getSynthLogic(input)!);
    }

    // find any named signals sitting around that don't do anything
    // this is not necessary for functionality, just nice naming inclusion
    logicsToTraverse.addAll(
      module.internalSignals
          .where((element) => element.naming != Naming.unnamed),
    );

    // make sure floating modules are included
    for (final subModule in module.subModules) {
      _getSynthSubModuleInstantiation(subModule);
      logicsToTraverse
        // ignore: invalid_use_of_protected_member
        ..addAll(subModule.inputs.values)
        ..addAll(subModule.outputs.values);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      final receiver = logicsToTraverse[i];
      if (receiver is LogicArray) {
        logicsToTraverse.addAll(receiver.elements);
      }

      if (receiver.isArrayMember) {
        logicsToTraverse.add(receiver.parentStructure!);
      }

      final driver = receiver.srcConnection;

      final receiverIsConstant = driver == null && receiver is Const;

      final receiverIsModuleInput =
          module.isInput(receiver) && !receiver.isArrayMember;
      final receiverIsModuleOutput =
          module.isOutput(receiver) && !receiver.isArrayMember;
      // final driverIsModuleInput = driver != null && module.isInput(driver);
      // final driverIsModuleOutput = driver != null && module.isOutput(driver);

      final synthReceiver = _getSynthLogic(receiver)!;
      final synthDriver = _getSynthLogic(driver);

      if (receiverIsModuleInput) {
        inputs.add(synthReceiver);
      } else if (receiverIsModuleOutput) {
        outputs.add(synthReceiver);
      } else {
        internalNets.add(synthReceiver);
      }

      final receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleOutput) {
        final subModule = receiver.parentModule!;
        // final subModuleInstantiation =
        //     _getSynthSubModuleInstantiation(subModule);
        // subModuleInstantiation.outputMapping[synthReceiver] = receiver; //TODO!

        // ignore: invalid_use_of_protected_member
        logicsToTraverse.addAll(subModule.inputs.values);
      } else if (driver != null) {
        if (!module.isInput(receiver)) {
          // stop at the input to this module
          logicsToTraverse.add(driver);
          assignments.add(_SynthAssignment(synthDriver!, synthReceiver));
        }
        // } else if (receiverIsConstant && receiver.value.isValid) {
        //   assignments.add(_SynthAssignment(receiver.value, synthReceiver));
      } else if (receiverIsConstant && !receiver.value.isFloating) {
        // this is a const that is valid, *partially* invalid (e.g. 0b1z1x0),
        // or anything that's not *entirely* floating (since those we can leave
        // as completely undriven).

        // make a new const node, it will merge away if not needed
        final newReceiverConst = _getSynthLogic(Const(receiver.value))!;
        internalNets.add(newReceiverConst);
        assignments.add(_SynthAssignment(newReceiverConst, synthReceiver));

        // assignments.add(_SynthAssignment(receiver.value, synthReceiver));
      }

      // final receiverIsSubModuleInput =
      //     receiver.isInput && (receiver.parentModule?.parent == module);
      // if (receiverIsSubModuleInput) {
      //   final subModule = receiver.parentModule!;
      //   final subModuleInstantiation =
      //       _getSynthSubModuleInstantiation(subModule);
      //   subModuleInstantiation.inputMapping[synthReceiver] = receiver;
      // }
    }

    _collapseAssignments();

    _assignSubmodulePortMapping();

    _collapseChainableModules();

    _pickSignalNames();
  }

  void _assignSubmodulePortMapping() {
    for (final submoduleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final input in submoduleInstantiation.module.inputs.values) {
        final synthInput = logicToSynthMap[input.srcConnection]!;
        submoduleInstantiation.inputMapping[input.name] = synthInput;
      }

      for (final output in submoduleInstantiation.module.outputs.values) {
        final synthOutput = logicToSynthMap[output]!;
        submoduleInstantiation.outputMapping[output.name] = synthOutput;
      }
    }
  }

  void _pickSignalNames() {
    // first ports get priority
    for (final input in inputs) {
      input.pickName(_synthInstantiationNameUniquifier); //, preReserved: true);
    }
    for (final output in outputs) {
      output
          .pickName(_synthInstantiationNameUniquifier); //, preReserved: true);
    }

    //TODO: eliminate internalNets that are replaced by inline!

    // then *reserved* internal signals get priority
    final nonReserved = <_SynthLogic>[];
    for (final signal in internalNets) {
      if (signal.isReserved) {
        signal.pickName(_synthInstantiationNameUniquifier);
      } else {
        nonReserved.add(signal);
      }
    }

    // then the rest of the internal signals
    for (final signal in nonReserved) {
      signal.pickName(_synthInstantiationNameUniquifier);
    }
  }

  // TODO: refactor this method to use synthLogic instead of name!
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
        .map(_getSynthSubModuleInstantiation);

    // number of times each signal name is used by any module
    final signalUsage = <_SynthLogic, int>{};

    // final synthModuleInputNames = inputs.map((inputSynth) => inputSynth.name);
    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final inputSynthLogic
          in subModuleInstantiation.inputMapping.values) {
        // final inputSynthLogicName = inputSynthLogic.name;
        if (inputs.contains(inputSynthLogic)) {
          // dont worry about inputs to THIS module
          continue;
        }

        signalUsage.update(
          inputSynthLogic,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final singleUseSignals = <_SynthLogic>{};
    signalUsage.forEach((signal, signalUsageCount) {
      // don't collapse if:
      //  - used more than once
      //  - inline modules for preferred names
      if (signalUsageCount == 1 && signal.mergeable) {
        singleUseSignals.add(signal);
      }
    });

    final singleUsageInlineableSubmoduleInstantiations =
        inlineableSubmoduleInstantiations.where((submoduleInstantiation) =>
            singleUseSignals // inlineable modules have 1 output
                .contains(submoduleInstantiation.outputMapping.values.first));

    // TODO: can subModule instantiations have expressions in ports?? they should i think

    // keep track of who is using it so we can not violate any rules
    // final inlineUsagesOfSingleUseSignals =
    //     <_SynthLogic, Set<_SynthSubModuleInstantiation>>{};

    // remove any inlineability for those that want no expressions
    for (final submoduleInstantiation in inlineableSubmoduleInstantiations) {
      singleUseSignals.removeAll(
          (submoduleInstantiation.module as CustomSystemVerilog)
              .expressionlessInputs
              .map((e) => submoduleInstantiation.inputMapping[e]!));

      // for (final inputSynthLogic
      //     in submoduleInstantiation.inputMapping.values) {
      //   inlineUsagesOfSingleUseSignals.update(
      //     inputSynthLogic,
      //     (users) => users..add(submoduleInstantiation),
      //     ifAbsent: () => {submoduleInstantiation},
      //   );
      // }
    }

    final synthLogicToInlineableSynthSubmoduleMap =
        <_SynthLogic, _SynthSubModuleInstantiation>{};
    for (final submoduleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      final outputSynthLogic =
          submoduleInstantiation.outputMapping.values.first;
      // ..clearDeclaration();

      // clear declaration of intermediate signal replaced by inline
      internalNets.remove(outputSynthLogic);

      // clear declaration of instantiation for inline module
      submoduleInstantiation.clearDeclaration();

      synthLogicToInlineableSynthSubmoduleMap[outputSynthLogic] =
          submoduleInstantiation;
    }

    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      subModuleInstantiation._synthLogicToInlineableSynthSubmoduleMap =
          synthLogicToInlineableSynthSubmoduleMap;
    }
  }

  void _collapseAssignments() {
    // there might be more assign statements than necessary, so let's ditch them
    var prevAssignmentCount = 0;
    while (prevAssignmentCount != assignments.length) {
      // keep looping until it stops shrinking
      final reducedAssignments = <_SynthAssignment>[];
      for (final assignment in assignments) {
        final dst = assignment.dst;
        final src = assignment.src;

        assert(dst != src,
            'No circular assignment allowed between $dst and $src.');

        final mergedAway = _SynthLogic.tryMerge(dst, src);

        //TODO: each time we merge one away, we need to update any remaining assignments!!

        if (mergedAway != null) {
          final kept = mergedAway == dst ? src : dst;

          // update all other assignments with the new one
          for (final otherAssignment in assignments) {
            // it's ok to replace it on the current one too, for clarity/debug
            otherAssignment.notifyReplace(mergedAway, kept);
          }

          final foundInternal = internalNets.remove(mergedAway);
          if (!foundInternal) {
            final foundKept = internalNets.remove(kept);
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
            }
          }
        } else if (assignment.src.isFloatingConstant) {
          //TODO: test that assignment to Z doesnt happen
          internalNets.remove(assignment.src);
        } else {
          reducedAssignments.add(assignment);
        }

        // if (src != null) {
        //   if (dst.renameable && src.renameable) {
        //     if (Module.isUnpreferred(dst.name)) {
        //       dst.mergeName(src);
        //     } else {
        //       src.mergeName(dst);
        //     }
        //   } else if (dst.renameable) {
        //     dst.mergeName(src);
        //   } else if (src.renameable) {
        //     src.mergeName(dst);
        //   } else {
        //     reducedAssignments.add(assignment);
        //   }
        // } else if (dst.renameable && Module.isUnpreferred(dst.name)) {
        //   // src is a constant, feed that string directly in
        //   // but only if this isn't a preferred signal (e.g. bus subset)
        //   dst.mergeConst(assignment.srcName());
        // } else {
        //   // nothing can be done here, keep it as-is
        //   reducedAssignments.add(assignment);
        // }
      }
      prevAssignmentCount = assignments.length;
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }

    // update the look-up table post-merge
    logicToSynthMap.clear();
    for (final synthLogic in [...inputs, ...outputs, ...internalNets]) {
      for (final logic in synthLogic.logics) {
        logicToSynthMap[logic] = synthLogic;
      }
    }
  }
}

class _SynthLogicArrayElement extends _SynthLogic {
  /// The [_SynthLogic] tracking the name of the direct parent array.
  final _SynthLogic parentArray;

  // @override
  // bool get _needsDeclaration => false;

  @override
  String get name => '${parentArray.name}[${logic.arrayIndex!}]';

  final Logic logic;

  _SynthLogicArrayElement(this.logic, this.parentArray)
      : assert(logic.isArrayMember,
            'Should only be used for elements in a LogicArray'),
        super(logic); //, '**ARRAY_ELEMENT**', renameable: false);
}

/// Represents a logic signal in the generated code within a module.
class _SynthLogic {
  // final Logic logic;

  List<Logic> get logics => UnmodifiableListView([
        if (_reservedLogic != null) _reservedLogic!,
        if (_constLogic != null) _constLogic!,
        if (_renameableLogic != null) _renameableLogic!,
        ..._mergeableLogics,
        ..._unnamedLogics,
      ]);

  bool get isReserved => _reservedLogic != null;

  Logic? _reservedLogic;
  Const? _constLogic;
  Logic? _renameableLogic;
  final Set<Logic> _mergeableLogics = {};
  final Set<Logic> _unnamedLogics = {};

  //TODO: consider if a Const gets thrown inside this...
  //TODO: maybe we should have different lists and allow overrides based on module port and context?

  String? _name;

  /// Set to `true` if a [Naming.reserved] is in here.
  // bool _containsReserved;
  // bool _containsRenameable;
  // bool _containsConst;

  /// Two [_SynthLogic]s that are not [mergeable] cannot be merged with each
  /// other. If onlyt one of them is not [mergeable], it can adopt the elements
  /// from the other.
  bool get mergeable =>
      _reservedLogic == null && _constLogic == null && _renameableLogic == null;

  /// True only if
  final bool isArray;

  // !(_containsConst || _containsReserved || _containsRenameable);

  // final bool _renameable;
  // bool get renameable => _mergedNameSynthLogic?.renameable ?? _renameable;

  // bool _needsDeclaration = true;
  // bool get needsDeclaration => _needsDeclaration;

  // _SynthLogic? _mergedNameSynthLogic;
  // String? _mergedConst;

  /// Must call [pickName] before this is accessible.
  String get name => _name!;

  void pickName(Uniquifier uniquifier) {
    assert(_name == null, 'Should only pick a name once.');

    // if (preReserved) {
    //   _name = _reservedLogic!.name;

    //   assert(!uniquifier.isAvailable(name),
    //       'Should be unavailable if prereserved.');
    // } else {
    _name = _findName(uniquifier);
    // }
  }

  String _findName(Uniquifier uniquifier) {
    assert(!isFloatingConstant, 'Should not be using floating constants.');

    // check for const
    if (_constLogic != null) {
      if (!_constNameDisallowed) {
        return _constLogic!.value.toString();
      } else {
        assert(
            logics.length > 1,
            'If there is a consant, but the const name is not allowed, '
            'there needs to be another option');
      }
    }

    // check for reserved
    if (_reservedLogic != null) {
      return uniquifier.getUniqueName(
          initialName: _reservedLogic!.name, reserved: true);
    }

    // check for renameable
    if (_renameableLogic != null) {
      return uniquifier.getUniqueName(initialName: _renameableLogic!.name);
    }

    // pick a preferred, available, mergeable name, if one exists
    final unpreferredMergeableLogics = <Logic>[];
    final uniquifiableMergeableLogics = <Logic>[];
    for (final mergeableLogic in _mergeableLogics) {
      if (Naming.isUnpreferred(mergeableLogic.name)) {
        unpreferredMergeableLogics.add(mergeableLogic);
      } else if (!uniquifier.isAvailable(mergeableLogic.name)) {
        uniquifiableMergeableLogics.add(mergeableLogic);
      } else {
        return uniquifier.getUniqueName(initialName: mergeableLogic.name);
      }
    }

    // uniquify a preferred, mergeable name, if one exists
    if (uniquifiableMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: uniquifiableMergeableLogics.first.name);
    }

    // pick an available unpreferred mergeable name, if one exists, otherwise
    // uniquify an unpreferred mergeable name
    if (unpreferredMergeableLogics.isNotEmpty) {
      return uniquifier.getUniqueName(
          initialName: unpreferredMergeableLogics
                  .firstWhereOrNull(
                      (element) => uniquifier.isAvailable(element.name))
                  ?.name ??
              unpreferredMergeableLogics.first.name);
    }

    // pick anything (unnamed) and uniquify as necessary (considering preferred)
    // no need to prefer an available one here, since it's all unnamed
    return uniquifier.getUniqueName(
        initialName: _unnamedLogics
                .firstWhereOrNull(
                    (element) => !Naming.isUnpreferred(element.name))
                ?.name ??
            _unnamedLogics.first.name);
  }

  /// If set, then this should never pick the constant as the name.
  bool get constNameDisallowed => _constNameDisallowed;
  bool _constNameDisallowed;

  _SynthLogic(Logic initialLogic,
      {Naming? namingOverride, bool constNameDisallowed = false})
      : isArray = initialLogic is LogicArray,
        _constNameDisallowed = constNameDisallowed {
    _addLogic(initialLogic, namingOverride: namingOverride);
  }

  /// Returns the [_SynthLogic] that should be *removed*.
  static _SynthLogic? tryMerge(_SynthLogic a, _SynthLogic b) {
    if (_constantsMergeable(a, b)) {
      // case to avoid things like a constant assigned to another constant
      a.adopt(b);
      return b;
    }

    if (!a.mergeable && !b.mergeable) {
      return null;
    }

    if (b.mergeable) {
      a.adopt(b);
      return b;
    } else {
      b.adopt(a);
      return a;
    }
  }

  static bool _constantsMergeable(_SynthLogic a, _SynthLogic b) =>
      a.isConstant &&
      b.isConstant &&
      a._constLogic!.value == b._constLogic!.value &&
      !a._constNameDisallowed &&
      !b._constNameDisallowed;

  void adopt(_SynthLogic other) {
    assert(other.mergeable || _constantsMergeable(this, other),
        'Cannot merge a non-mergeable into this.');
    assert(other.isArray == isArray, 'Cannot merge arrays and non-arrays');

    // other._logics.forEach(_addLogic);

    _constNameDisallowed |= other._constNameDisallowed;

    // only take one of the other's items if we don't have it already
    _constLogic ??= other._constLogic;
    _reservedLogic ??= other._reservedLogic;
    _renameableLogic ??= other._renameableLogic;

    // the rest, take them all
    _mergeableLogics.addAll(other._mergeableLogics);
    _unnamedLogics.addAll(other._unnamedLogics);
  }

  /// Assignments should be eliminated rather than assign to `z`, so this
  /// indicates if this [_SynthLogic] is actually pointing to a [Const] that
  /// is floating.
  bool get isFloatingConstant => _constLogic?.value.isFloating ?? false;

  bool get isConstant => _constLogic != null;

  bool get needsDeclaration => !(isConstant && !_constNameDisallowed);

  void _addLogic(Logic logic, {Naming? namingOverride}) {
    final naming = namingOverride ?? logic.naming;
    if (logic is Const) {
      _constLogic = logic;
    } else {
      switch (naming) {
        case Naming.reserved:
          _reservedLogic = logic;
          break;
        case Naming.renameable:
          _renameableLogic = logic;
          break;
        case Naming.mergeable:
          _mergeableLogics.add(logic);
          break;
        case Naming.unnamed:
          _unnamedLogics.add(logic);
          break;
      }
    }
  }

  //  {bool renameable = true})
  //     : _renameable = renameable &&
  //           // don't rename arrays since its elements would need updating too
  //           logic is! LogicArray;

  /// Gets the best "original" name for a collection of merged [_SynthLogic]s.
  // String get originalName {
  //   assert(
  //       _needsDeclaration,
  //       'This only works for the "head" of the linked-list of merging,'
  //       ' which is the one needing declaration');

  //   String? renameableName;
  //   String? mergeableName;
  //   String? unnamedName;

  //   _SynthLogic? nextSynthLogic = this;
  //   // TODO: prefer a different mergeable name to renaming the first mergeable

  //   while (nextSynthLogic != null) {
  //     final nextName = nextSynthLogic.logic.name;
  //     switch (nextSynthLogic.logic.namingConfiguration) {
  //       case LogicNaming.reserved:
  //         // Should not merge multiple reserved, so just short-circuit here
  //         return nextName;
  //       case LogicNaming.renameable:
  //         assert(
  //             renameableName == null, 'Should not merge multiple renameable');
  //         renameableName = nextName;
  //         break;
  //       case LogicNaming.mergeable:
  //         // prefer the first one we find
  //         mergeableName ??= nextName;
  //         break;
  //       case LogicNaming.unnamed:
  //         // prefer the first one we find
  //         unnamedName ??= nextName;
  //         break;
  //     }

  //     nextSynthLogic = nextSynthLogic._mergedNameSynthLogic;
  //   }

  //   return renameableName ??
  //       mergeableName ??
  //       unnamedName!; // must be one of these...
  // }

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'}, '
      'logics contained: ${logics.map((e) => e.name).toList()}';

  // void clearDeclaration() {
  //   _needsDeclaration = false;
  // }

  // void mergeName(_SynthLogic other) {
  //   // print("Renaming $name to ${other.name}");
  //   if (!renameable) {
  //     throw Exception('This _SynthLogic ($this) cannot be renamed to $other.');
  //   }
  //   _mergedConst = null;
  //   _mergedNameSynthLogic
  //       ?.mergeName(this); // in case we're changing direction of merge
  //   _mergedNameSynthLogic = other;
  //   _needsDeclaration = false;
  // }

  // void mergeConst(String constant) {
  //   // print("Renaming $name to const ${constant}");
  //   if (!renameable) {
  //     throw Exception(
  //         'This _SynthLogic ($this) cannot be renamed to $constant.');
  //   }
  //   _mergedNameSynthLogic
  //       ?.mergeConst(constant); // in case we're changing direction of merge
  //   _mergedNameSynthLogic = null;
  //   _mergedConst = constant;
  //   _needsDeclaration = false;
  // }

  static String _widthToRangeDef(int width, {bool forceRange = false}) {
    if (width > 1 || forceRange) {
      return '[${width - 1}:0]';
    } else {
      return '';
    }
  }

  /// Computes the name of the signal at declaration time with appropriate
  /// dimensions included.
  String definitionName() {
    String packedDims;
    String unpackedDims;

    // we only use this for dimensions, so first is fine
    final logic = logics.first;

    if (isArray) {
      final logicArr = logic as LogicArray;

      final packedDimsBuf = StringBuffer();
      final unpackedDimsBuf = StringBuffer();

      final dims = logicArr.dimensions;
      for (var i = 0; i < dims.length; i++) {
        final dim = dims[i];
        final dimStr = _widthToRangeDef(dim, forceRange: true);
        if (i < logicArr.numUnpackedDimensions) {
          unpackedDimsBuf.write(dimStr);
        } else {
          packedDimsBuf.write(dimStr);
        }
      }

      packedDimsBuf.write(_widthToRangeDef(logicArr.elementWidth));

      packedDims = packedDimsBuf.toString();
      unpackedDims = unpackedDimsBuf.toString();
    } else {
      packedDims = _widthToRangeDef(logic.width);
      unpackedDims = '';
    }

    return [packedDims, name, unpackedDims]
        .where((e) => e.isNotEmpty)
        .join(' ');
  }
}

class _SynthAssignment {
  _SynthLogic get dst => _dst;
  _SynthLogic _dst;
  _SynthLogic get src => _src;
  _SynthLogic _src;

  _SynthAssignment(this._src, this._dst);

  @override
  String toString() => '$dst <= $src';

  void notifyReplace(_SynthLogic oldSynthLogic, _SynthLogic newSynthLogic) {
    if (_dst == oldSynthLogic) {
      _dst = newSynthLogic;
    }

    if (_src == oldSynthLogic) {
      _src = newSynthLogic;
    }
  }

  // String srcName() {
  //   if (_src is int) {
  //     return _src.toString();
  //   } else if (_src is LogicValue) {
  //     return (_src as LogicValue).toString();
  //   } else if (_src is _SynthLogic) {
  //     return (_src as _SynthLogic).name;
  //   } else {
  //     throw Exception("Don't know how to synthesize value: $_src");
  //   }
  // }
}
