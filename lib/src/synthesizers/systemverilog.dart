/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// systemverilog.dart
/// Definition for SystemVerilog Synthesizer
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

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
    module.inputs.forEach((signalName, logic) {
      connections.add('.$signalName(${inputs[signalName]})');
    });
    module.outputs.forEach((signalName, logic) {
      connections.add('.$signalName(${outputs[signalName]})');
    });
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
        .toList();
    return declarations;
  }

  List<String> _verilogOutputs() {
    final declarations = _synthModuleDefinition.outputs
        .map((sig) => 'output logic ${sig.definitionName()}')
        .toList();
    return declarations;
  }

  String _verilogInternalNets() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalNets) {
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
          .add('assign ${assignment.dst.name} = ${assignment.srcName()};');
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
  final Map<_SynthLogic, Logic> inputMapping = {};
  final Map<_SynthLogic, Logic> outputMapping = {};
  bool _needsDeclaration = true;
  bool get needsDeclaration => _needsDeclaration;
  Map<String, _SynthSubModuleInstantiation>?
      _synthLogicNameToInlineableSynthSubmoduleMap;
  _SynthSubModuleInstantiation(this.module, this.name);

  @override
  String toString() =>
      "_SynthSubModuleInstantiation '$name', module name:'${module.name}'";

  void clearDeclaration() {
    _needsDeclaration = false;
  }

  Map<String, String> _moduleInputsMap() =>
      inputMapping.map((synthLogic, logic) => MapEntry(
          logic.name, // port name guaranteed to match
          _synthLogicNameToInlineableSynthSubmoduleMap?[synthLogic.name]
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
      outputMapping.map((synthLogic, logic) => MapEntry(
          logic.name, // port name guaranteed to match
          synthLogic.name)),
    );
  }
}

/// Represents the definition of a module.
class _SynthModuleDefinition {
  final Module module;
  final List<_SynthAssignment> assignments = [];
  final Set<_SynthLogic> internalNets = {};
  final Set<_SynthLogic> inputs = {};
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
  late final Uniquifier _synthInstantiationNameUniquifier;

  String _getUniqueSynthLogicName(String? initialName, bool portName) {
    if (portName && initialName == null) {
      throw Exception('Port name cannot be null.');
    }
    return _synthInstantiationNameUniquifier.getUniqueName(
        initialName: initialName, reserved: portName);
  }

  String _getUniqueSynthSubModuleInstantiationName(
          String? initialName, bool reserved) =>
      _synthInstantiationNameUniquifier.getUniqueName(
          initialName: initialName, nullStarter: 'm', reserved: reserved);

  _SynthLogic? _getSynthLogic(Logic? logic, bool allowPortName) {
    if (logic == null) {
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      final newSynth = _SynthLogic(
          logic, _getUniqueSynthLogicName(logic.name, allowPortName),
          renameable: !allowPortName);
      logicToSynthMap[logic] = newSynth;
      return newSynth;
    }
  }

  _SynthModuleDefinition(this.module) {
    _synthInstantiationNameUniquifier = Uniquifier(
        reservedNames: {...module.inputs.keys, ...module.outputs.keys});

    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values);
    for (final output in module.outputs.values) {
      outputs.add(_getSynthLogic(output, true)!);
    }

    // make sure disconnected inputs are included
    for (final input in module.inputs.values) {
      inputs.add(_getSynthLogic(input, true)!);
    }

    // make sure floating modules are included
    for (final subModule in module.subModules) {
      _getSynthSubModuleInstantiation(subModule);
      logicsToTraverse
        ..addAll(subModule.inputs.values)
        ..addAll(subModule.outputs.values);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      final receiver = logicsToTraverse[i];
      final driver = receiver.srcConnection;

      final receiverIsModuleInput = module.isInput(receiver);
      final receiverIsModuleOutput = module.isOutput(receiver);
      final driverIsModuleInput = driver != null && module.isInput(driver);
      final driverIsModuleOutput = driver != null && module.isOutput(driver);

      final synthReceiver = _getSynthLogic(
          receiver, receiverIsModuleInput || receiverIsModuleOutput)!;
      final synthDriver =
          _getSynthLogic(driver, driverIsModuleInput || driverIsModuleOutput);

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
        subModuleInstantiation.outputMapping[synthReceiver] = receiver;

        for (final element in subModule.inputs.values) {
          if (!logicsToTraverse.contains(element)) {
            logicsToTraverse.add(element);
          }
        }
      } else if (driver != null) {
        if (!module.isInput(receiver)) {
          // stop at the input to this module
          if (!logicsToTraverse.contains(driver)) {
            logicsToTraverse.add(driver);
          }
          assignments.add(_SynthAssignment(synthDriver, synthReceiver));
        }
      } else if (driver == null && receiver.value.isValid) {
        assignments.add(_SynthAssignment(receiver.value, synthReceiver));
      } else if (driver == null && !receiver.value.isFloating) {
        // this is a signal that is *partially* invalid (e.g. 0b1z1x0)
        assignments.add(_SynthAssignment(receiver.value, synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;
        final subModuleInstantiation =
            _getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.inputMapping[synthReceiver] = receiver;
      }
    }

    _collapseAssignments();

    _collapseChainableModules();
  }

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

    final signalNameUsage = <String,
        int>{}; // number of times each signal name is used by any module
    final synthModuleInputNames = inputs.map((inputSynth) => inputSynth.name);
    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (final inputSynthLogic in subModuleInstantiation.inputMapping.keys) {
        final inputSynthLogicName = inputSynthLogic.name;
        if (synthModuleInputNames.contains(inputSynthLogicName)) {
          // dont worry about inputs to THIS module
          continue;
        }
        if (!signalNameUsage.containsKey(inputSynthLogicName)) {
          signalNameUsage[inputSynthLogicName] = 1;
        } else {
          signalNameUsage[inputSynthLogicName] =
              signalNameUsage[inputSynthLogicName]! + 1;
        }
      }
    }

    var singleUseNames = <String>{};
    signalNameUsage.forEach((signalName, signalUsageCount) {
      if (signalUsageCount == 1) {
        singleUseNames.add(signalName);
      }
    });

    // don't collapse inline modules for preferred names
    singleUseNames = singleUseNames.where(Module.isUnpreferred).toSet();

    final singleUsageInlineableSubmoduleInstantiations =
        inlineableSubmoduleInstantiations.where((submoduleInstantiation) =>
            singleUseNames.contains(
                submoduleInstantiation.outputMapping.keys.first.name));

    final synthLogicNameToInlineableSynthSubmoduleMap =
        <String, _SynthSubModuleInstantiation>{};
    for (final submoduleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      final outputSynthLogic = submoduleInstantiation.outputMapping.keys.first
        ..clearDeclaration();
      submoduleInstantiation.clearDeclaration();
      synthLogicNameToInlineableSynthSubmoduleMap[outputSynthLogic.name] =
          submoduleInstantiation;
    }

    for (final subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      subModuleInstantiation._synthLogicNameToInlineableSynthSubmoduleMap =
          synthLogicNameToInlineableSynthSubmoduleMap;
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
        final src = assignment._src is _SynthLogic
            ? assignment._src as _SynthLogic
            : null;
        if (dst.name == src?.name) {
          throw Exception(
              'Circular assignment detected between $dst and $src.');
        }
        if (src != null) {
          if (dst.renameable && src.renameable) {
            if (Module.isUnpreferred(dst.name)) {
              dst.mergeName(src);
            } else {
              src.mergeName(dst);
            }
          } else if (dst.renameable) {
            dst.mergeName(src);
          } else if (src.renameable) {
            src.mergeName(dst);
          } else {
            reducedAssignments.add(assignment);
          }
        } else if (dst.renameable) {
          // src is a constant, feed that string directly in
          dst.mergeConst(assignment.srcName());
        } else {
          // nothing can be done here, keep it as-is
          reducedAssignments.add(assignment);
        }
      }
      prevAssignmentCount = assignments.length;
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }
}

/// Represents a logic signal in the generated code within a module.
class _SynthLogic {
  final Logic logic;
  final String _name;
  final bool _renameable;
  bool get renameable => _mergedNameSynthLogic?.renameable ?? _renameable;
  bool _needsDeclaration = true;
  _SynthLogic? _mergedNameSynthLogic;
  String? _mergedConst;
  bool get needsDeclaration => _needsDeclaration;
  String get name => _mergedNameSynthLogic?.name ?? _mergedConst ?? _name;

  _SynthLogic(this.logic, this._name, {bool renameable = true})
      : _renameable = renameable;

  @override
  String toString() => "'$name', logic name: '${logic.name}'";

  void clearDeclaration() {
    _needsDeclaration = false;
    _mergedNameSynthLogic?.clearDeclaration();
  }

  void mergeName(_SynthLogic other) {
    // print("Renaming $name to ${other.name}");
    if (!renameable) {
      throw Exception('This _SynthLogic ($this) cannot be renamed to $other.');
    }
    _mergedConst = null;
    _mergedNameSynthLogic
        ?.mergeName(this); // in case we're changing direction of merge
    _mergedNameSynthLogic = other;
    _needsDeclaration = false;
  }

  void mergeConst(String constant) {
    // print("Renaming $name to const ${constant}");
    if (!renameable) {
      throw Exception(
          'This _SynthLogic ($this) cannot be renamed to $constant.');
    }
    _mergedNameSynthLogic
        ?.mergeConst(constant); // in case we're changing direction of merge
    _mergedNameSynthLogic = null;
    _mergedConst = constant;
    _needsDeclaration = false;
  }

  String definitionName() {
    if (logic.width > 1) {
      return '[${logic.width - 1}:0] $name';
    } else {
      return name;
    }
  }
}

class _SynthAssignment {
  final _SynthLogic dst;
  final dynamic _src;
  _SynthAssignment(this._src, this.dst);

  @override
  String toString() => '${dst.name} <= ${srcName()}';

  String srcName() {
    if (_src is int) {
      return _src.toString();
    } else if (_src is LogicValue) {
      return (_src as LogicValue).toString();
    } else if (_src is _SynthLogic) {
      return (_src as _SynthLogic).name;
    } else {
      throw Exception("Don't know how to synthesize value: $_src");
    }
  }
}
