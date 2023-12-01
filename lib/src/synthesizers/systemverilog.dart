// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog.dart
// Definition for SystemVerilog Synthesizer
//
// 2021 August 26
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

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
      connections.add('.$signalName(${inputs[signalName]!})');
    }

    for (final signalName in module.outputs.keys) {
      connections.add('.$signalName(${outputs[signalName]!})');
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

  /// The main [_SynthModuleDefinition] for this.
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

  /// Representation of all input port declarations in generated SV.
  List<String> _verilogInputs() {
    final declarations = _synthModuleDefinition.inputs
        .map((sig) => 'input logic ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all output port declarations in generated SV.
  List<String> _verilogOutputs() {
    final declarations = _synthModuleDefinition.outputs
        .map((sig) => 'output logic ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all internal net declarations in generated SV.
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

  /// Representation of all assignments in generated SV.
  String _verilogAssignments() {
    final assignmentLines = <String>[];
    for (final assignment in _synthModuleDefinition.assignments) {
      assignmentLines
          .add('assign ${assignment.dst.name} = ${assignment.src.name};');
    }
    return assignmentLines.join('\n');
  }

  /// Representation of all sub-module instantiations in generated SV.
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

  /// The contents of this module converted to SystemVerilog without module
  /// declaration, ports, etc.
  String _verilogModuleContents(Map<Module, String> moduleToInstanceTypeMap) =>
      [
        _verilogInternalNets(),
        _verilogAssignments(),
        _verilogSubModuleInstantiations(moduleToInstanceTypeMap),
      ].where((element) => element.isNotEmpty).join('\n');

  /// The representation of all port declarations.
  String _verilogPorts() => [
        ..._verilogInputs(),
        ..._verilogOutputs(),
      ].join(',\n');

  /// The full SV representation of this module.
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
  /// The module represented.
  final Module module;

  /// The name of this instance.
  String? _name;

  /// Must call [pickName] before this is accessible.
  String get name => _name!;

  /// Selects a name for this module instance. Must be called exactly once.
  void pickName(Uniquifier uniquifier) {
    assert(_name == null, 'Should only pick a name once.');

    _name = uniquifier.getUniqueName(
      initialName: module.uniqueInstanceName,
      reserved: module.reserveName,
      nullStarter: 'm',
    );
  }

  /// A mapping of input port name to [_SynthLogic].
  final Map<String, _SynthLogic> inputMapping = {};

  /// A mapping of output port name to [_SynthLogic].
  final Map<String, _SynthLogic> outputMapping = {};

  /// Indicates whether this module should be declared.
  bool get needsDeclaration => _needsDeclaration;
  bool _needsDeclaration = true;

  /// Removes the need for this module to be declared (via [needsDeclaration]).
  void clearDeclaration() {
    _needsDeclaration = false;
  }

  /// Mapping from [_SynthLogic]s which are outputs of inlineable SV to those
  /// inlineable modules.
  late final Map<_SynthLogic, _SynthSubModuleInstantiation>
      _synthLogicToInlineableSynthSubmoduleMap;

  /// Creates an instantiation for [module].
  _SynthSubModuleInstantiation(this.module);

  @override
  String toString() =>
      "_SynthSubModuleInstantiation ${_name == null ? 'null' : '"$name"'}, "
      "module name:'${module.name}'";

  /// Provides a mapping from input ports of this module to a string that can
  /// be fed into that port, which may include inline SV modules as well.
  Map<String, String> _moduleInputsMap() =>
      inputMapping.map((name, synthLogic) => MapEntry(
          name,
          _synthLogicToInlineableSynthSubmoduleMap[synthLogic]
                  ?.inlineVerilog() ??
              synthLogic.name));

  /// Provides the inline SV representation for this module.
  ///
  /// Should only be called if [module] is [InlineSystemVerilog].
  String inlineVerilog() =>
      '(${(module as InlineSystemVerilog).inlineVerilog(_moduleInputsMap())})';

  /// Provides the full SV instantiation for this module.
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
  /// The [Module] being defined.
  final Module module;

  final List<_SynthAssignment> assignments = [];

  /// All other internal signals that are not ports.
  ///
  /// This is the only collection that maye have mergeable items in it.
  final Set<_SynthLogic> internalNets = {};

  /// All the input ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<_SynthLogic> inputs = {};

  /// All the output ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<_SynthLogic> outputs = {};

  /// A mapping from original [Logic]s to the [_SynthLogic]s that represent
  /// them.
  final Map<Logic, _SynthLogic> logicToSynthMap = {};

  /// A mapping from the original [Module]s to the
  /// [_SynthSubModuleInstantiation]s that represent them.
  final Map<Module, _SynthSubModuleInstantiation>
      moduleToSubModuleInstantiationMap = {};

  /// Either accesses a previously created [_SynthSubModuleInstantiation]
  /// corresponding to [m], or else creates a new one and adds it to the
  /// [moduleToSubModuleInstantiationMap].
  _SynthSubModuleInstantiation _getSynthSubModuleInstantiation(Module m) {
    if (moduleToSubModuleInstantiationMap.containsKey(m)) {
      return moduleToSubModuleInstantiationMap[m]!;
    } else {
      final newSSMI = _SynthSubModuleInstantiation(m);
      moduleToSubModuleInstantiationMap[m] = newSSMI;
      return newSSMI;
    }
  }

  @override
  String toString() => "module name: '${module.name}'";

  /// Used to uniquify any identifiers, including signal names
  /// and module instances.
  final Uniquifier _synthInstantiationNameUniquifier;

  /// Either accesses a previously created [_SynthLogic] corresponding to
  /// [logic], or else creates a new one and adds it to the [logicToSynthMap].
  _SynthLogic? _getSynthLogic(
    Logic? logic,
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

        newSynth = _SynthLogicArrayElement(logic, parentArraySynthLogic!);
      } else {
        final disallowConstName = logic.isInput &&
            logic.parentModule is CustomSystemVerilog &&
            (logic.parentModule! as CustomSystemVerilog)
                .expressionlessInputs
                .contains(logic.name);

        newSynth = _SynthLogic(
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

  /// Creates a new definition representation for this [module].
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
        final subModuleInstantiation =
            _getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.outputMapping[receiver.name] = synthReceiver;

        // ignore: invalid_use_of_protected_member
        logicsToTraverse.addAll(subModule.inputs.values);
      } else if (driver != null) {
        if (!module.isInput(receiver)) {
          // stop at the input to this module
          logicsToTraverse.add(driver);
          assignments.add(_SynthAssignment(synthDriver!, synthReceiver));
        }
      } else if (receiverIsConstant && !receiver.value.isFloating) {
        // this is a const that is valid, *partially* invalid (e.g. 0b1z1x0),
        // or anything that's not *entirely* floating (since those we can leave
        // as completely undriven).

        // make a new const node, it will merge away if not needed
        final newReceiverConst = _getSynthLogic(Const(receiver.value))!;
        internalNets.add(newReceiverConst);
        assignments.add(_SynthAssignment(newReceiverConst, synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;
        final subModuleInstantiation =
            _getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.inputMapping[receiver.name] = synthReceiver;
      }
    }

    // The order of these is important!
    _collapseAssignments();
    _assignSubmodulePortMapping();
    _collapseChainableModules();
    _pickNames();
  }

  /// Updates all sub-module instantiations with information about which
  /// [_SynthLogic] should be used for their ports.
  void _assignSubmodulePortMapping() {
    for (final submoduleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      // ignore: invalid_use_of_protected_member
      for (final inputName in submoduleInstantiation.module.inputs.keys) {
        final orig = submoduleInstantiation.inputMapping[inputName]!;
        submoduleInstantiation.inputMapping[inputName] =
            orig.replacement ?? orig;
      }

      for (final outputName in submoduleInstantiation.module.outputs.keys) {
        final orig = submoduleInstantiation.outputMapping[outputName]!;
        submoduleInstantiation.outputMapping[outputName] =
            orig.replacement ?? orig;
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

    // pick names of *reserved* submodule instances
    final nonReservedSubmodules = <_SynthSubModuleInstantiation>[];
    for (final submodule in moduleToSubModuleInstantiationMap.values) {
      if (submodule.module.reserveName) {
        submodule.pickName(_synthInstantiationNameUniquifier);
      } else {
        nonReservedSubmodules.add(submodule);
      }
    }

    // then *reserved* internal signals get priority
    final nonReservedSignals = <_SynthLogic>[];
    for (final signal in internalNets) {
      if (signal.isReserved) {
        signal.pickName(_synthInstantiationNameUniquifier);
      } else {
        nonReservedSignals.add(signal);
      }
    }

    // then submodule instances
    for (final submodule in nonReservedSubmodules) {
      submodule.pickName(_synthInstantiationNameUniquifier);
    }

    // then the rest of the internal signals
    for (final signal in nonReservedSignals) {
      signal.pickName(_synthInstantiationNameUniquifier);
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
        .map(_getSynthSubModuleInstantiation);

    // number of times each signal name is used by any module
    final signalUsage = <_SynthLogic, int>{};

    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final inputSynthLogic
          in subModuleInstantiation.inputMapping.values) {
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
        inlineableSubmoduleInstantiations
            .where((submoduleInstantiation) => singleUseSignals.contains(
                // inlineable modules have only 1 output
                submoduleInstantiation.outputMapping.values.first));

    // remove any inlineability for those that want no expressions
    for (final submoduleInstantiation in inlineableSubmoduleInstantiations) {
      singleUseSignals.removeAll(
          (submoduleInstantiation.module as CustomSystemVerilog)
              .expressionlessInputs
              .map((e) => submoduleInstantiation.inputMapping[e]!));
    }

    final synthLogicToInlineableSynthSubmoduleMap =
        <_SynthLogic, _SynthSubModuleInstantiation>{};
    for (final submoduleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      final outputSynthLogic =
          // inlineable modules have only 1 output
          submoduleInstantiation.outputMapping.values.first;

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

  /// Collapses assignments that don't need to remain present.
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

        if (mergedAway != null) {
          final kept = mergedAway == dst ? src : dst;

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
          internalNets.remove(assignment.src);
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
    for (final synthLogic in [...inputs, ...outputs, ...internalNets]) {
      for (final logic in synthLogic.logics) {
        logicToSynthMap[logic] = synthLogic;
      }
    }
  }
}

/// Represents an element of a [LogicArray].
///
/// Does not fully override or properly implement all characteristics of
/// [_SynthLogic], so this should be used cautiously.
class _SynthLogicArrayElement extends _SynthLogic {
  /// The [_SynthLogic] tracking the name of the direct parent array.
  final _SynthLogic parentArray;

  @override
  bool get needsDeclaration => false;

  @override
  String get name => '${parentArray.name}[${logic.arrayIndex!}]';

  /// The element of the [parentArray].
  final Logic logic;

  /// Creates an instance of an element of a [LogicArray].
  _SynthLogicArrayElement(this.logic, this.parentArray)
      : assert(logic.isArrayMember,
            'Should only be used for elements in a LogicArray'),
        super(logic);
}

/// Represents a logic signal in the generated code within a module.
class _SynthLogic {
  /// All [Logic]s represented, regardless of type.
  List<Logic> get logics => UnmodifiableListView([
        if (_reservedLogic != null) _reservedLogic!,
        if (_constLogic != null) _constLogic!,
        if (_renameableLogic != null) _renameableLogic!,
        ..._mergeableLogics,
        ..._unnamedLogics,
      ]);

  /// If this was merged and is now replaced by another, then this is non-null
  /// and points to it.
  _SynthLogic? get replacement => _replacement?.replacement ?? _replacement;
  set replacement(_SynthLogic? newReplacement) {
    _replacement?.replacement = newReplacement;
    _replacement = newReplacement;
  }

  _SynthLogic? _replacement;

  /// Indicates that this has a reserved name.
  bool get isReserved => _reservedLogic != null;

  /// The [Logic] whose name is reserved, if there is one.
  Logic? _reservedLogic;

  /// The [Logic] whose name is renameable, if there is one.
  Logic? _renameableLogic;

  /// [Logic]s that are marked mergeable.
  final Set<Logic> _mergeableLogics = {};

  /// [Logic]s that are unnamed.
  final Set<Logic> _unnamedLogics = {};

  /// The [Logic] whose value represents a constant, if there is one.
  Const? _constLogic;

  /// Assignments should be eliminated rather than assign to `z`, so this
  /// indicates if this [_SynthLogic] is actually pointing to a [Const] that
  /// is floating.
  bool get isFloatingConstant => _constLogic?.value.isFloating ?? false;

  /// Whether this represents a constant.
  bool get isConstant => _constLogic != null;

  /// If set, then this should never pick the constant as the name.
  bool get constNameDisallowed => _constNameDisallowed;
  bool _constNameDisallowed;

  /// Whether this signal should be declared.
  bool get needsDeclaration => !(isConstant && !_constNameDisallowed);

  /// Two [_SynthLogic]s that are not [mergeable] cannot be merged with each
  /// other. If onlyt one of them is not [mergeable], it can adopt the elements
  /// from the other.
  bool get mergeable =>
      _reservedLogic == null && _constLogic == null && _renameableLogic == null;

  /// True only if this represents a [LogicArray].
  final bool isArray;

  /// The chosen name of this.
  ///
  /// Must call [pickName] before this is accessible.
  String get name => _name!;
  String? _name;

  /// Picks a [name].
  ///
  /// Must be called exactly once.
  void pickName(Uniquifier uniquifier) {
    assert(_name == null, 'Should only pick a name once.');

    _name = _findName(uniquifier);
  }

  /// Finds the best name from the collection of [Logic]s.
  String _findName(Uniquifier uniquifier) {
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

  /// Creates an instance to represent [initialLogic] and any that merge
  /// into it.
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

  /// Indicates whether two constants can be merged.
  static bool _constantsMergeable(_SynthLogic a, _SynthLogic b) =>
      a.isConstant &&
      b.isConstant &&
      a._constLogic!.value == b._constLogic!.value &&
      !a._constNameDisallowed &&
      !b._constNameDisallowed;

  /// Merges [other] to be represented by `this` instead, and updates the
  /// [other] that it has been replaced.
  void adopt(_SynthLogic other) {
    assert(other.mergeable || _constantsMergeable(this, other),
        'Cannot merge a non-mergeable into this.');
    assert(other.isArray == isArray, 'Cannot merge arrays and non-arrays');

    _constNameDisallowed |= other._constNameDisallowed;

    // only take one of the other's items if we don't have it already
    _constLogic ??= other._constLogic;
    _reservedLogic ??= other._reservedLogic;
    _renameableLogic ??= other._renameableLogic;

    // the rest, take them all
    _mergeableLogics.addAll(other._mergeableLogics);
    _unnamedLogics.addAll(other._unnamedLogics);

    // keep track that it was replaced by this
    other.replacement = this;
  }

  /// Adds a new [logic] to be represented by this.
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

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'}, '
      'logics contained: ${logics.map((e) => e.name).toList()}';

  /// Provides a definition for a range in SV from a width.
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

/// Represents an assignment between two signals.
class _SynthAssignment {
  _SynthLogic _dst;

  /// The destination being driven by this assignment.
  ///
  /// Ensures it's always using the most up-to-date version.
  _SynthLogic get dst {
    if (_dst.replacement != null) {
      _dst = _dst.replacement!;
      assert(_dst.replacement == null, 'should not be a chain...');
    }
    return _dst;
  }

  _SynthLogic _src;

  /// The source driving in this assignment.
  ///
  /// Ensures it's always using the most up-to-date version.
  _SynthLogic get src {
    if (_src.replacement != null) {
      _src = _src.replacement!;
      assert(_src.replacement == null, 'should not be a chain...');
    }
    return _src;
  }

  /// Constructs a representation of an assignment.
  _SynthAssignment(this._src, this._dst);

  @override
  String toString() => '$dst <= $src';
}
