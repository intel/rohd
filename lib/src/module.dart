// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module.dart
// Definition for abstract module class.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/timestamper.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a synthesizable hardware entity with clearly defined interface
/// boundaries.
///
/// Any hardware to be synthesized must be contained within a [Module].
/// This construct is similar to a SystemVerilog `module`.
abstract class Module {
  /// The name of this [Module].
  ///
  /// This is not necessarily the same as the instance name in generated code.
  /// For that, see [uniqueInstanceName].  If you set [reserveName], then it
  /// is guaranteed to match or else the [build] will fail.
  final String name;

  /// An internal list of sub-modules.
  final Set<Module> _modules = {};

  /// An internal list of internal-signals.
  ///
  /// Used for waveform dump efficiency.
  final Set<Logic> _internalSignals = HashSet<Logic>();

  /// An internal list of inputs to this [Module].
  final Map<String, Logic> _inputs = HashMap<String, Logic>();

  /// An internal list of outputs to this [Module].
  final Map<String, Logic> _outputs = HashMap<String, Logic>();

  /// The parent [Module] of this [Module].
  ///
  /// This only gets populated after its parent [Module], if it exists, has
  /// been built.
  Module? get parent => _parent;

  /// A cached copy of the parent, useful for debug and efficiency
  Module? _parent;

  /// A map from input port names to this [Module] to corresponding [Logic]
  /// signals.
  @protected
  Map<String, Logic> get inputs => UnmodifiableMapView<String, Logic>(_inputs);

  /// A map from output port names to this [Module] to corresponding [Logic]
  /// signals.
  Map<String, Logic> get outputs =>
      UnmodifiableMapView<String, Logic>(_outputs);

  /// An [Iterable] of all [Module]s contained within this [Module].
  ///
  /// This only gets populated after this [Module] has been built.
  Iterable<Module> get subModules => UnmodifiableListView<Module>(_modules);

  /// An [Iterable] of all [Logic]s contained within this [Module] which are
  /// *not* an input or output port of this [Module].
  ///
  /// This does not contain any signals within submodules.
  Iterable<Logic> get internalSignals =>
      UnmodifiableListView<Logic>(_internalSignals);

  /// An [Iterable] of all [Logic]s contained within this [Module], including
  /// inputs, outputs, and internal signals of this [Module].
  ///
  /// This does not contain any signals within submodules.
  Iterable<Logic> get signals => CombinedListView([
        UnmodifiableListView(_inputs.values),
        UnmodifiableListView(_outputs.values),
        UnmodifiableListView(internalSignals),
      ]);

  /// Accesses the [Logic] associated with this [Module]s input port
  /// named [name].
  ///
  /// Only logic within this [Module] should consume this signal.
  @protected
  Logic input(String name) => _inputs.containsKey(name)
      ? _inputs[name]!
      : throw Exception(
          'Input name "$name" not found as an input to this Module.');

  /// Provides the [input] named [name] if it exists, otherwise `null`.
  ///
  /// Only logic within this [Module] should consume this signal.
  @protected
  Logic? tryInput(String name) => _inputs[name];

  /// Accesses the [Logic] associated with this [Module]s output port
  /// named [name].
  ///
  /// Logic outside of this [Module] should consume this signal.  It is okay
  /// to consume this within this [Module] as well.
  Logic output(String name) => _outputs.containsKey(name)
      ? _outputs[name]!
      : throw Exception(
          'Output name "$name" not found as an output of this Module.');

  /// Provides the [output] named [name] if it exists, otherwise `null`.
  Logic? tryOutput(String name) => _outputs[name];

  /// Returns true iff [net] is the same [Logic] as the input port of this
  /// [Module] with the same name.
  bool isInput(Logic net) =>
      _inputs[net.name] == net ||
      (net.isArrayMember && isInput(net.parentStructure!));

  /// Returns true iff [net] is the same [Logic] as the output port of this
  /// [Module] with the same name.
  bool isOutput(Logic net) =>
      _outputs[net.name] == net ||
      (net.isArrayMember && isOutput(net.parentStructure!));

  /// Returns true iff [net] is the same [Logic] as an input or output port of
  /// this [Module] with the same name.
  bool isPort(Logic net) => isInput(net) || isOutput(net);

  /// If this module has a [parent], after [build] this will be a guaranteed
  /// unique name within its scope.
  String get uniqueInstanceName => hasBuilt || reserveName
      ? _uniqueInstanceName
      : throw ModuleNotBuiltException(
          'Module must be built to access uniquified name.'
          '  Call build() before accessing this.');
  String _uniqueInstanceName;

  /// Return string type definition name if validation passed
  /// else throw exception.
  ///
  /// This validation method ensure that [name] is valid if
  /// [reserveName] set to `true`.
  static String? _nameValidation(String? name, bool reserveName) {
    if (reserveName && name == null) {
      throw NullReservedNameException();
    } else if (reserveName && name!.isEmpty) {
      throw EmptyReservedNameException();
    } else if (reserveName && !Sanitizer.isSanitary(name!)) {
      throw InvalidReservedNameException();
    } else {
      return name;
    }
  }

  /// If true, guarantees [uniqueInstanceName] matches [name] or else the
  /// [build] will fail.
  final bool reserveName;

  /// The definition name of this [Module] used when instantiating instances in
  /// generated code.
  ///
  /// By default, if none is provided at construction time, the definition name
  /// is the same as the [runtimeType].
  ///
  /// This could become uniquified by a [Synthesizer] unless
  /// [reserveDefinitionName] is set.
  String get definitionName =>
      Sanitizer.sanitizeSV(_definitionName ?? runtimeType.toString());

  final String? _definitionName;

  /// If true, guarantees [definitionName] is maintained by a [Synthesizer],
  /// or else it will fail.
  final bool reserveDefinitionName;

  /// Constructs a new [Module] with instance name [name] and definition
  /// name [definitionName].
  ///
  /// If [reserveName] is set, then the model will not build if it's unable
  /// to keep from uniquifying (changing) [name] to avoid conflicts.
  ///
  /// If [reserveDefinitionName] is set, then code generation will fail if
  /// it is unable to keep from uniquifying [definitionName] to avoid conflicts.
  Module(
      {this.name = 'unnamed_module',
      this.reserveName = false,
      String? definitionName,
      this.reserveDefinitionName = false})
      : _uniqueInstanceName = _nameValidation(name, reserveName) ?? name,
        _definitionName =
            _nameValidation(definitionName, reserveDefinitionName);

  /// Returns an [Iterable] of [Module]s representing the hierarchical path to
  /// this [Module].
  ///
  /// The first element of the [Iterable] is the top-most hierarchy.
  /// The last element of the [Iterable] is this [Module].
  /// Only returns valid information after [build].
  Iterable<Module> hierarchy() {
    if (!hasBuilt) {
      throw ModuleNotBuiltException(
          'Module must be built before accessing hierarchy.'
          '  Call build() before executing this.');
    }
    Module? pModule = this;
    final hierarchyQueue = Queue<Module>();
    while (pModule != null) {
      hierarchyQueue.addFirst(pModule);
      pModule = pModule.parent;
    }
    return hierarchyQueue;
  }

  /// Indicates whether this [Module] has had the [build()] method called on it.
  bool get hasBuilt => _hasBuilt;
  bool _hasBuilt = false;

  /// Builds the [Module] and all [subModules] within it.
  ///
  /// It is recommended not to override [build()] nor put logic in [build()]
  /// unless you have good reason to do so.  Aim to build up relevant logic in
  /// the constructor.
  ///
  /// All logic within this [Module] *must* be defined *before* the call to
  /// `super.build()`.  When overriding this method, you should call
  /// `super.build()` as the last thing that you do, and you must always call
  /// it.
  ///
  /// This method traverses connectivity inwards from this [Module]'s [inputs]
  /// and [outputs] to determine which [Module]s are contained within it.
  /// During this process, it will set a variety of additional information
  /// within the hierarchy.
  ///
  /// This function can be used to consume real wallclock time for things like
  /// starting up interactions with independent processes (e.g. cosimulation).
  ///
  /// This function should only be called one time per [Module].
  ///
  /// The hierarchy is built "bottom-up", so leaf-level [Module]s are built
  /// before the [Module]s which contain them.
  @mustCallSuper
  Future<void> build() async {
    if (hasBuilt) {
      throw Exception(
          'This Module has already been built, and can only be built once.');
    }

    // construct the list of modules within this module
    // 1) trace from outputs of this module back to inputs of this module
    for (final output in _outputs.values) {
      await _traceOutputForModuleContents(output, dontAddSignal: true);
    }
    // 2) trace from inputs of all modules to inputs of this module
    for (final input in _inputs.values) {
      await _traceInputForModuleContents(input, dontAddSignal: true);
    }

    // set unique module instance names for submodules
    final uniquifier = Uniquifier();
    for (final module in _modules) {
      module._uniqueInstanceName = uniquifier.getUniqueName(
          initialName: Sanitizer.sanitizeSV(module.name),
          reserved: module.reserveName);
    }

    _hasBuilt = true;
  }

  /// Adds a [Module] to this as a subModule.
  Future<void> _addAndBuildModule(Module module) async {
    if (module.parent != null) {
      throw Exception('This Module "$this" already has a parent. '
          'If you are hitting this as a user of ROHD, please file '
          'a bug at https://github.com/intel/rohd/issues.');
    }

    _modules.add(module);

    module._parent = this;
    await module.build();
  }

  /// A prefix to add to the beginning of any port name that is "unpreferred".
  static String get _unpreferredPrefix => '_';

  /// Makes a signal name "unpreferred" when considering between multiple
  /// possible signal names.
  ///
  /// When logic is synthesized out (e.g. to SystemVerilog), there are cases
  /// where two signals might be logically equivalent (e.g. directly connected
  /// to each other).  In those scenarios, one of the two signals is collapsed
  /// into the other.  If one of the two signals is "unpreferred", it will
  /// choose the other one for the final signal name.  Marking signals as
  /// "unpreferred" can have the effect of making generated output easier to
  /// read.
  @protected
  static String unpreferredName(String name) => _unpreferredPrefix + name;

  /// Returns true iff the signal name is "unpreferred".
  ///
  /// See documentation for [unpreferredName] for more details.
  static bool isUnpreferred(String name) => name.startsWith(_unpreferredPrefix);

  /// Searches for [Logic]s and [Module]s within this [Module] from its inputs.
  Future<void> _traceInputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isOutput(signal)) {
      return;
    }

    if (!signal.isInput && !signal.isOutput && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    final subModule = signal.isInput ? signal.parentModule : null;

    final subModuleParent = subModule?.parent;

    if (!dontAddSignal && signal.isOutput) {
      // somehow we have reached the output of a module which is not a submodule
      // nor this module, bad!
      throw Exception('Violation of input/output rules in $this on $signal.'
          '  Logic within a Module should only consume inputs and drive outputs'
          ' of that Module.  See https://github.com/intel/rohd#modules for'
          ' more information.');
    }

    if (subModule != this && subModuleParent != null) {
      // we've already parsed down this path
      return;
    }

    if (subModule != null &&
        subModule != this &&
        (subModuleParent == null || subModuleParent == this)) {
      // if the subModuleParent hasn't been set, or it is the current module,
      // then trace it
      if (subModuleParent != this) {
        await _addAndBuildModule(subModule);
      }
      for (final subModuleOutput in subModule._outputs.values) {
        await _traceInputForModuleContents(subModuleOutput,
            dontAddSignal: true);
      }
      for (final subModuleInput in subModule._inputs.values) {
        await _traceOutputForModuleContents(subModuleInput,
            dontAddSignal: true);
      }
    } else {
      if (!dontAddSignal && !isInput(signal) && subModule == null) {
        _addInternalSignal(signal);
      }

      if (!dontAddSignal && isInput(signal)) {
        throw Exception('Input $signal of module $this is dependent on'
            ' another input of the same module.');
      }

      for (final dstConnection in signal.dstConnections) {
        if (signal.isOutput &&
            dstConnection.isOutput &&
            signal.parentModule! == dstConnection.parentModule!) {
          // since both are outputs, we can't easily use them to
          // check if they have already been traversed, so we must
          // explicitly check that we're not running them back-to-back.
          // another iteration will take care of continuing the trace
          continue;
        }

        await _traceInputForModuleContents(dstConnection);
      }
    }
  }

  /// Searches for [Logic]s and [Module]s within this [Module] from its outputs.
  Future<void> _traceOutputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isInput(signal)) {
      return;
    }

    if (!signal.isInput && !signal.isOutput && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    final subModule = signal.isOutput ? signal.parentModule : null;

    final subModuleParent = subModule?.parent;

    if (!dontAddSignal && signal.isInput) {
      // somehow we have reached the input of a module which is not a submodule
      // nor this module, bad!
      throw Exception('Violation of input/output rules in $this on $signal.'
          '  Logic within a Module should only consume inputs and drive outputs'
          ' of that Module.'
          '  See https://github.com/intel/rohd#modules for more information.');
    }

    if (subModule != this && subModuleParent != null) {
      // we've already parsed down this path
      return;
    }

    if (subModule != null &&
        subModule != this &&
        (subModuleParent == null || subModuleParent == this)) {
      // if the subModuleParent hasn't been set, or it is the current module,
      // then trace it
      if (subModuleParent != this) {
        await _addAndBuildModule(subModule);
      }
      for (final subModuleInput in subModule._inputs.values) {
        await _traceOutputForModuleContents(subModuleInput,
            dontAddSignal: true);
      }
      for (final subModuleOutput in subModule._outputs.values) {
        await _traceInputForModuleContents(subModuleOutput,
            dontAddSignal: true);
      }
    } else {
      if (!dontAddSignal && !isOutput(signal) && subModule == null) {
        _addInternalSignal(signal);
        for (final dstConnection in signal.dstConnections) {
          await _traceInputForModuleContents(dstConnection);
        }
      }

      if (signal is LogicStructure) {
        for (final srcConnection in signal.srcConnections) {
          await _traceOutputForModuleContents(srcConnection);
        }
      } else if (signal.srcConnection != null) {
        await _traceOutputForModuleContents(signal.srcConnection!);
      }
    }
  }

  /// Registers a signal as an internal signal.
  void _addInternalSignal(Logic signal) {
    assert(!signal.isPort, 'Should not be adding a port as an internal signal');

    _internalSignals.add(signal);

    // ignore: invalid_use_of_protected_member
    signal.parentModule = this;
  }

  /// Checks whether a port name is safe to add (e.g. no duplicates).
  void _checkForSafePortName(String name) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    if (outputs.containsKey(name) || inputs.containsKey(name)) {
      throw Exception('Already defined a port with name "$name".');
    }
  }

  /// Registers a signal as an input to this [Module] and returns an input port
  /// that can be consumed.
  ///
  /// The return value is the same as what is returned by [input()].
  @protected
  Logic addInput(String name, Logic x, {int width = 1}) {
    _checkForSafePortName(name);
    if (x.width != width) {
      throw PortWidthMismatchException(x, width);
    }

    if (x is LogicStructure) {
      // ignore: parameter_assignments
      x = x.packed;
    }

    final inPort = Port(name, width)
      ..gets(x)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _inputs[name] = inPort;

    return inPort;
  }

  /// Registers and returns an input [LogicArray] port to this [Module] with
  /// the specified [dimensions], [elementWidth], and [numUnpackedDimensions]
  /// named [name].
  ///
  /// This is very similar to [addInput], except for [LogicArray]s.
  ///
  /// Performs validation on overall width matching for [x], but not on
  /// [dimensions], [elementWidth], or [numUnpackedDimensions].
  @protected
  LogicArray addInputArray(
    String name,
    Logic x, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _checkForSafePortName(name);

    final inArr = LogicArray(dimensions, elementWidth,
        name: name, numUnpackedDimensions: numUnpackedDimensions)
      ..gets(x)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _inputs[name] = inArr;

    return inArr;
  }

  /// Registers an output to this [Module] and returns an output port that
  /// can be driven.
  ///
  /// The return value is the same as what is returned by [output()].
  @protected
  Logic addOutput(String name, {int width = 1}) {
    _checkForSafePortName(name);

    final outPort = Port(name, width)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _outputs[name] = outPort;

    return outPort;
  }

  /// Registers and returns an output [LogicArray] port to this [Module] with
  /// the specified [dimensions], [elementWidth], and [numUnpackedDimensions]
  /// named [name].
  ///
  /// This is very similar to [addOutput], except for [LogicArray]s.
  @protected
  LogicArray addOutputArray(
    String name, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _checkForSafePortName(name);

    final outArr = LogicArray(dimensions, elementWidth,
        name: name, numUnpackedDimensions: numUnpackedDimensions)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _outputs[name] = outArr;

    return outArr;
  }

  @override
  String toString() => '"$name" ($runtimeType)  :'
      '  ${_inputs.keys} => ${_outputs.keys}';

  /// Returns a pretty-print [String] of the heirarchy of all [Module]s within
  /// this [Module].
  String hierarchyString([int indent = 0]) {
    final padding = List.filled(indent, '  ').join();
    final hier = StringBuffer('$padding> ${toString()}');
    for (final module in _modules) {
      hier.write('\n${module.hierarchyString(indent + 1)}');
    }
    return hier.toString();
  }

  /// Returns a synthesized version of this [Module].
  ///
  /// Currently returns one long file in SystemVerilog, but in the future
  /// may have other output formats, languages, files, etc.
  String generateSynth() {
    if (!_hasBuilt) {
      throw ModuleNotBuiltException();
    }

    final synthHeader = '''
/**
 * Generated by ROHD - www.github.com/intel/rohd
 * Generation time: ${Timestamper.stamp()}
 * ROHD Version: ${Config.version}
 */

''';
    return synthHeader +
        SynthBuilder(this, SystemVerilogSynthesizer())
            .getFileContents()
            .join('\n\n////////////////////\n\n');
  }
}

extension _ModuleLogicStructureUtils on LogicStructure {
  /// Provides a list of all source connections of all elements within
  /// this structure, recursively.
  ///
  /// Useful for searching during [Module] build.
  Iterable<Logic> get srcConnections => [
        for (final element in elements)
          if (element is LogicStructure)
            ...element.srcConnections
          else if (element.srcConnection != null)
            element.srcConnection!
      ];
}
