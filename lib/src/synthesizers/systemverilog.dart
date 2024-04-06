// Copyright (C) 2021-2024 Intel Corporation
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
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// A [Synthesizer] which generates equivalent SystemVerilog as the
/// given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible.
class SystemVerilogSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) =>
      // ignore: deprecated_member_use_from_same_package
      !((module is CustomSystemVerilog) ||
          (module is SystemVerilog && !module.generatesDefinition));

  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name
  /// [instanceName].
  ///
  /// [ports] maps [module] input/output/inout names to a verilog signal name.
  ///
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [ports] should be:
  /// ports:  `{ 'a' : 'sig_a', 'b' : 'sig_b', 'c' : 'sig_c'}`
  static String instantiationVerilogFor(
      {required Module module,
      required String instanceType,
      required String instanceName,
      required Map<String, String> ports,
      Map<String, String>? parameters,
      bool forceStandardInstantiation = false}) {
    if (!forceStandardInstantiation) {
      if (module is SystemVerilog) {
        //TODO: test this path
        return module.instantiationVerilog(
          instanceType,
          instanceName,
          ports,
        );
      }
      // ignore: deprecated_member_use_from_same_package
      else if (module is CustomSystemVerilog) {
        //TODO: test this path
        return module.instantiationVerilog(
          instanceType,
          instanceName,
          Map.fromEntries(ports.entries
              // ignore: invalid_use_of_protected_member
              .where((element) => module.inputs.containsKey(element.key))),
          Map.fromEntries(ports.entries
              .where((element) => module.outputs.containsKey(element.key))),
        );
      }
    }

    //non-custom needs more details
    final connections = <String>[];

    // ignore: invalid_use_of_protected_member
    for (final signalName in module.inputs.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
    }

    for (final signalName in module.outputs.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
    }

    // ignore: invalid_use_of_protected_member
    for (final signalName in module.inOuts.keys) {
      connections.add('.$signalName(${ports[signalName]!})');
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

  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name
  /// [instanceName].
  ///
  /// [inputs] and [outputs] map `module` input/output name to a verilog signal
  /// name.
  ///
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [inputs] and [outputs] should be:
  /// inputs:  `{ 'a' : 'sig_a', 'b' : 'sig_b'}`
  /// outputs: `{ 'c' : 'sig_c' }`
  @Deprecated('Use `instantiationVerilogFor` instead.')
  static String instantiationVerilogWithParameters(
          Module module,
          String instanceType,
          String instanceName,
          Map<String, String> inputs,
          Map<String, String> outputs,
          {Map<String, String> inOuts = const {},
          Map<String, String>? parameters,
          bool forceStandardInstantiation = false}) =>
      instantiationVerilogFor(
        module: module,
        instanceType: instanceType,
        instanceName: instanceName,
        ports: {...inputs, ...outputs, ...inOuts},
        parameters: parameters,
        forceStandardInstantiation: forceStandardInstantiation,
      );

  @override
  SynthesisResult synthesize(
          Module module, Map<Module, String> moduleToInstanceTypeMap) =>
      module is SystemVerilog && module.generatesDefinition
          ? _SystemVerilogCustomDefinitionSynthesisResult(
              module, moduleToInstanceTypeMap)
          : _SystemVerilogSynthesisResult(module, moduleToInstanceTypeMap);
}

/// Allows a [Module] to define a custom implementation of SystemVerilog to be
/// injected in generated output instead of instantiating a separate `module`.
//TODO: update docs with new recommendations
//TODO: make sure test cover both old and new version
@Deprecated('Use `SystemVerilog` instead')
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
  final List<String> expressionlessInputs = const []; //TODO: test this old one
}

/// Allows a [Module] to define a custom implementation of SystemVerilog to be
/// injected in generated output instead of instantiating a separate `module`.
mixin SystemVerilog on Module {
  /// Generates custom SystemVerilog to be injected in place of a `module`
  /// instantiation.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively of the module that would have been instantiated had it not
  /// been overridden.  [ports] is a mapping from the [Module]'s port names to
  /// the names of the signals that are passed into those ports in the generated
  /// SystemVerilog.
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  );

  /// A list of names of [input]s which should not have any SystemVerilog
  /// expressions (including constants) in-lined into them. Only signal names
  /// will be fed into these.
  @protected
  final List<String> expressionlessInputs = const []; //TODO: test this new one

  //TODO: doc
  /// If `null`, no definition generated...
  /// must consistently generate the same thing (whats the word for that? isosomething)
  String? definitionVerilog(String definitionType) => null;

  //TODO
  bool get generatesDefinition => definitionVerilog('*PLACEHOLDER*') != null;
}

/// Allows a [Module] to define a special type of [SystemVerilog] which can be
/// inlined within other SystemVerilog code.
///
/// The inline SystemVerilog will get parentheses wrapped around it and then
/// dropped into other code in the same way a variable name is.
mixin InlineSystemVerilog on Module implements SystemVerilog {
  /// Generates custom SystemVerilog to be injected in place of the output
  /// port's corresponding signal name.
  ///
  /// The [inputs] are a mapping from the [Module]'s port names to the names of
  /// the signals that are passed into those ports in the generated
  /// SystemVerilog. It will only contain [input]s and [inOut]s, as there
  /// should only be one [output] which is driven by the expression.
  ///
  /// The output will be appropriately wrapped with parentheses to guarantee
  /// proper order of operations.
  String inlineVerilog(Map<String, String> inputs);

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    if (outputs.length != 1) {
      throw Exception(
          'Inline verilog must have exactly one output, but saw $outputs.');
    }
    final output = ports[outputs.keys.first];
    final inputPorts = Map.fromEntries(ports.entries.where((element) =>
        inputs.containsKey(element.key) || inOuts.containsKey(element.key)));
    final inline = inlineVerilog(inputPorts);
    return 'assign $output = $inline;  // $instanceName';
  }

  @override
  @protected
  final List<String> expressionlessInputs = const [];

  @override
  String? definitionVerilog(String definitionType) => null;

  @override
  bool get generatesDefinition => definitionVerilog('*PLACEHOLDER*') != null;
}

//TODO: doc
class _SystemVerilogCustomDefinitionSynthesisResult extends SynthesisResult {
  _SystemVerilogCustomDefinitionSynthesisResult(
      super.module, super.moduleToInstanceTypeMap)
      : assert(module is SystemVerilog && module.generatesDefinition,
            'This should only be used for custom system verilog definitions.');

  @override
  int get matchHashCode =>
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!.hashCode;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is _SystemVerilogCustomDefinitionSynthesisResult &&
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')! ==
          (other.module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!;

  @override
  String toFileContents() => (module as SystemVerilog)
      .definitionVerilog(moduleToInstanceTypeMap[module]!)!;
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
    //TODO: do module definition and instances need different names?
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
        .map((sig) => 'input ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all output port declarations in generated SV.
  List<String> _verilogOutputs() {
    final declarations = _synthModuleDefinition.outputs
        .map((sig) => 'output ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all inout port declarations in generated SV.
  List<String> _verilogInOuts() {
    final declarations = _synthModuleDefinition.inOuts
        .map((sig) => 'inout ${sig.definitionType()} ${sig.definitionName()}')
        .toList(growable: false);
    return declarations;
  }

  /// Representation of all internal net declarations in generated SV.
  String _verilogInternalSignals() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalSignals
        .sorted((a, b) => a.name.compareTo(b.name))) {
      if (sig.needsDeclaration) {
        declarations.add('${sig.definitionType()} ${sig.definitionName()};');
      }
    }
    return declarations.join('\n');
  }

  /// Representation of all assignments in generated SV.
  String _verilogAssignments() {
    final assignmentLines = <String>[];
    for (final assignment in _synthModuleDefinition.assignments) {
      //TODO: include this assertion!
      // assert(
      //     !(assignment.src.isNet && assignment.dst.isNet),
      //     'Net connections should have been implemented as'
      //     ' bidirectional net connections.');

      //TODO: alias?
      if (assignment.src.isNet && assignment.dst.isNet) {
        // assignmentLines
        //     .add('alias ${assignment.dst.name} = ${assignment.src.name};');

        // assignmentLines
        //     .add('assign ${assignment.src.name} = ${assignment.dst.name};');
        // assignmentLines
        //     .add('assign ${assignment.dst.name} = ${assignment.src.name};');

        // assignmentLines
        //     .add('tran t1 (${assignment.src.name}, ${assignment.dst.name});');

        //TODO: THE PLAN:
        // - all net to net connections create a netalias module AND an assignment
        // - as assignments are collapsed, remove the netaliases
        // - after all assignments collapsed, remove any assignments between nets
        // - add a way for `SystemVerilog` to support adding a definition

        // assert(
        //     false); //This shouldnt happen i think? TODO make this an assertion
        assignmentLines
            .add('myalias ma(${assignment.dst.name}, ${assignment.src.name});');
      } else {
        assignmentLines
            .add('assign ${assignment.dst.name} = ${assignment.src.name};');
      }
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
        _verilogInternalSignals(),
        _verilogAssignments(),
        _verilogSubModuleInstantiations(moduleToInstanceTypeMap),
      ].where((element) => element.isNotEmpty).join('\n');

  /// The representation of all port declarations.
  String _verilogPorts() => [
        ..._verilogInputs(),
        ..._verilogOutputs(),
        ..._verilogInOuts(),
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
  late final Map<String, _SynthLogic> inputMapping =
      UnmodifiableMapView(_inputMapping);
  final Map<String, _SynthLogic> _inputMapping = {};

  /// Adds an input mapping from [name] to [synthLogic].
  void setInputMapping(String name, _SynthLogic synthLogic,
      {bool replace = false}) {
    // ignore: invalid_use_of_protected_member
    assert(module.inputs.containsKey(name),
        'Input $name not found in module ${module.name}.');
    assert(
        (replace && _inputMapping.containsKey(name)) ||
            !_inputMapping.containsKey(name),
        'A mapping already exists to this input: $name.');

    _inputMapping[name] = synthLogic;
  }

  /// A mapping of output port name to [_SynthLogic].
  late final Map<String, _SynthLogic> outputMapping =
      UnmodifiableMapView(_outputMapping);
  final Map<String, _SynthLogic> _outputMapping = {};

  /// Adds an output mapping from [name] to [synthLogic].
  void setOutputMapping(String name, _SynthLogic synthLogic,
      {bool replace = false}) {
    assert(module.outputs.containsKey(name),
        'Output $name not found in module ${module.name}.');
    assert(
        (replace && _outputMapping.containsKey(name)) ||
            !_outputMapping.containsKey(name),
        'A mapping already exists to this output: $name.');

    _outputMapping[name] = synthLogic;
  }

  /// A mapping of output port name to [_SynthLogic].
  final Map<String, _SynthLogic> inOutMapping = {};

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
      inOuts: inOutMapping.map((name, synthLogic) => MapEntry(
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
  final Set<_SynthLogic> internalSignals = {};

  /// All the input ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<_SynthLogic> inputs = {};

  /// All the output ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<_SynthLogic> outputs = {};

  /// All the output ports.
  ///
  /// This will *never* have any mergeable items in it.
  final Set<_SynthLogic> inOuts = {};

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
            // ignore: invalid_use_of_protected_member
            ...module.inOuts.keys,
          },
        ) {
    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values)
      // ignore: invalid_use_of_protected_member
      ..addAll(module.inOuts.values);

    for (final output in module.outputs.values) {
      outputs.add(_getSynthLogic(output)!);
    }

    // make sure disconnected inputs are included
    // ignore: invalid_use_of_protected_member
    for (final input in module.inputs.values) {
      inputs.add(_getSynthLogic(input)!);
    }

    // make sure disconnected inouts are included, also
    // ignore: invalid_use_of_protected_member
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
      _getSynthSubModuleInstantiation(subModule);
      logicsToTraverse
        // ignore: invalid_use_of_protected_member
        ..addAll(subModule.inputs.values)
        ..addAll(subModule.outputs.values)
        // ignore: invalid_use_of_protected_member
        ..addAll(subModule.inOuts.values);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      final receiver = logicsToTraverse[i];

      assert(receiver.parentModule != null,
          'Any signal traced by this should have been detected by build.');

      if (receiver.parentModule != module &&
          !module.subModules.contains(receiver.parentModule)) {
        print('in $module skipping $receiver');
        //TODO: this is bad! shouldn't happen!
        assert(false);
        continue;
      }

      // if (receiver.parentModule != module) {
      //   //TODO: is this ok?
      //   print(receiver);
      //   continue;
      // }
      // assert(receiver.parentModule == module); //TODO

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
        ].where((element) =>
            element.parentModule == module ||
            (element.isPort &&
                element.parentModule!.parent ==
                    module))); //TODO: is this right?

        // if (receiver.parentModule == module
        //     /*||
        //     (receiver.isInOut && receiver.parentModule?.parent == module)*/
        //     ) {
        for (final srcConnection in receiver.srcConnections) {
          if (srcConnection.parentModule == module ||
              ((srcConnection.isOutput || srcConnection.isInOut) &&
                  srcConnection.parentModule!.parent == module)) {
            // logicsToTraverse.add(srcConnection);

            final netSynthDriver = _getSynthLogic(srcConnection)!;

            assignments.add(_SynthAssignment(
              netSynthDriver,
              synthReceiver,
            ));
          }
          // }
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
        final subModuleInstantiation =
            _getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.inOutMapping[receiver.name] = synthReceiver;

        // ignore: invalid_use_of_protected_member
        logicsToTraverse.addAll(subModule.inOuts.values);
      }

      final receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleOutput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! _SynthLogicArrayElement) {
          _getSynthSubModuleInstantiation(subModule)
              .setOutputMapping(receiver.name, synthReceiver);
        }

        logicsToTraverse
          // ignore: invalid_use_of_protected_member
          ..addAll(subModule.inputs.values)
          // ignore: invalid_use_of_protected_member
          ..addAll(subModule.inOuts.values);
      } else if (driver != null) {
        if (!module.isInput(receiver) &&
            //TODO is this right?
            !module.isInOut(receiver)) {
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
        internalSignals.add(newReceiverConst);
        assignments.add(_SynthAssignment(newReceiverConst, synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;

        // array elements are not named ports, just contained in array
        if (synthReceiver is! _SynthLogicArrayElement) {
          _getSynthSubModuleInstantiation(subModule)
              .setInputMapping(receiver.name, synthReceiver);
        }
      }
    }

    // The order of these is important!
    _collapseAssignments();
    _assignSubmodulePortMapping();
    _updateNetConnections();
    _collapseChainableModules();
    _pickNames();
  }

  //TODO doc
  void _updateNetConnections() {
    // clear declarations for net connection modules which don't have a
    // corresponding assignment anymore
    for (final netConnectSynth in moduleToSubModuleInstantiationMap.entries
        .where((entry) => entry.key is NetConnect)
        .map((e) => e.value)) {
      final matchingAssignments = assignments
          .where((assignment) =>
              netConnectSynth.inOutMapping.containsValue(assignment.src) &&
              netConnectSynth.inOutMapping.containsValue(assignment.dst))
          .toList();

      if (matchingAssignments.isEmpty) {
        // if no assignments are present, then this connection was merged
        netConnectSynth.clearDeclaration();
      } else {
        // if some do exist, then we should keep the net connect but ditch the
        // other assignments
        matchingAssignments.forEach(assignments.remove);
        //TODO: should we do something more efficient than this removal on a list?
      }
    }

    //TODO KEEP
    // assert(
    //     assignments.firstWhereOrNull(
    //             (element) => element.src.isNet && element.dst.isNet) ==
    //         null,
    //     'No assignments should remain between nets.');

    // now clear out any internal signals not used by any assignment or
    // submodule anymore
    internalSignals.removeWhere((internalSignal) =>
        // don't remove arrays! //TODO is this right?
        !internalSignal.isArray &&
        // no assignment uses the signal
        (assignments.firstWhereOrNull((assignment) =>
                assignment.src == internalSignal ||
                assignment.dst == internalSignal) ==
            null) &&
        // no submodule instantiation uses the signal.
        (moduleToSubModuleInstantiationMap.values
                .where((submoduleSynthInstantiation) =>
                    submoduleSynthInstantiation.needsDeclaration)
                .firstWhereOrNull((submoduleSynthInstantiation) => [
                      ...submoduleSynthInstantiation.inputMapping.values,
                      ...submoduleSynthInstantiation.outputMapping.values,
                      ...submoduleSynthInstantiation.inOutMapping.values,
                    ].contains(internalSignal)) ==
            null));
  }

  /// Updates all sub-module instantiations with information about which
  /// [_SynthLogic] should be used for their ports.
  void _assignSubmodulePortMapping() {
    for (final submoduleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      // ignore: invalid_use_of_protected_member
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

      // ignore: invalid_use_of_protected_member
      for (final inOutName in submoduleInstantiation.module.inOuts.keys) {
        final orig = submoduleInstantiation.inOutMapping[inOutName]!;
        submoduleInstantiation.inOutMapping[inOutName] =
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
    for (final inOut in inOuts) {
      inOut.pickName(_synthInstantiationNameUniquifier);
    }

    // pick names of *reserved* submodule instances
    final nonReservedSubmodules = <_SynthSubModuleInstantiation>[];
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
    final nonReservedSignals = <_SynthLogic>[];
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
    for (final MapEntry(key: subModule, value: instantiation)
        in moduleToSubModuleInstantiationMap.entries) {
      if (subModule is SystemVerilog) {
        singleUseSignals.removeAll(subModule.expressionlessInputs
            .map((e) => instantiation.inputMapping[e]!));
      }
      // ignore: deprecated_member_use_from_same_package
      else if (subModule is CustomSystemVerilog) {
        singleUseSignals.removeAll(subModule.expressionlessInputs
            .map((e) => instantiation.inputMapping[e]!));
      }
    }

    final synthLogicToInlineableSynthSubmoduleMap =
        <_SynthLogic, _SynthSubModuleInstantiation>{};
    for (final submoduleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      final outputSynthLogic =
          // inlineable modules have only 1 output
          submoduleInstantiation.outputMapping.values.first;

      // clear declaration of intermediate signal replaced by inline
      internalSignals.remove(outputSynthLogic);

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

        //TODO: undriven wires should be deleted?

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

          //TODO
          // if (src.isNet && dst.isNet) {
          //   // if we've eliminated an assignment between nets, then remove the
          //   // net connection as well
          //   for (final logicNet in src.logics) {
          //     for (final dstConnection in logicNet.dstConnections) {
          //       if (dstConnection.isInOut &&
          //           dstConnection.parentModule is NetConnect &&
          //           dst.logics.contains(dstConnection
          //               .parentModule!
          //               // ignore: invalid_use_of_protected_member
          //               .inOuts
          //               .values
          //               .where((element) => element != dstConnection)
          //               .first
          //               .srcConnection)) {
          //         moduleToSubModuleInstantiationMap[dstConnection.parentModule]!
          //             .clearDeclaration();
          //       }
          //     }
          //   }
          // }
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

    // create net assignments to replace normal assignments
    // final nonNetAssignments = <_SynthAssignment>[];
    // for (final assignment in assignments) {
    //   if (assignment.src.isNet && assignment.dst.isNet) {
    //     _getSynthSubModuleInstantiation(NetConnect(
    //       assignment.dst.logics.first as LogicNet,
    //       assignment.src.logics.first as LogicNet,
    //     ));
    //   } else {
    //     nonNetAssignments.add(assignment);
    //   }
    // }
    // assignments
    //   ..clear()
    //   ..addAll(nonNetAssignments);

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
  String get name {
    final n = '${parentArray.name}[${logic.arrayIndex!}]';
    assert(
      Sanitizer.isSanitary(
          n.substring(0, n.contains('[') ? n.indexOf('[') : null)),
      'Array name should be sanitary, but found $n',
    );
    return n;
  }

  /// The element of the [parentArray].
  final Logic logic;

  /// Creates an instance of an element of a [LogicArray].
  _SynthLogicArrayElement(this.logic, this.parentArray)
      : assert(logic.isArrayMember,
            'Should only be used for elements in a LogicArray'),
        super(logic);

  @override
  String toString() => '${_name == null ? 'null' : '"$name"'},'
      ' parentArray=($parentArray), element ${logic.arrayIndex}, logic: $logic'
      ' logics contained: ${logics.map((e) => e.name).toList()}';
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

  /// Whether this represents a net.
  bool get isNet =>
      // can just look at the first since nets and non-nets cannot be merged
      logics.first is LogicNet ||
      (isArray && (logics.first as LogicArray).isNet);

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
  String get name {
    assert(_replacement == null,
        'If this has been replaced, then we should not be getting its name.');
    assert(isConstant || Sanitizer.isSanitary(_name!),
        'Signal names should be sanitary, but found $_name.');

    return _name!;
  }

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

    if (a.isNet != b.isNet) {
      // do not merge nets with non-nets
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

    //TODO: why is this assertion bad?
    // assert(
    //     other.logics.first.parentModule! == logics.first.parentModule! ||
    //         (other.logics.first.parentModule!.subModules
    //             .contains(logics.first.parentModule)) ||
    //         (logics.first.parentModule!.subModules
    //             .contains(other.logics.first.parentModule)),
    //     'Merged signals should be near each other');

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
        case Naming.renameable:
          _renameableLogic = logic;
        case Naming.mergeable:
          _mergeableLogics.add(logic);
        case Naming.unnamed:
          _unnamedLogics.add(logic);
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

  String definitionType() => isNet ? 'wire' : 'logic';

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
