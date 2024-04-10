// Copyright (C) 2021-2024 Intel Corporation
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
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/diagnostics/inspector_service.dart';
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
  final Set<Logic> _internalSignals = {};

  /// An internal list of inputs to this [Module].
  final Map<String, Logic> _inputs = {};

  /// An internal list of outputs to this [Module].
  final Map<String, Logic> _outputs = {};

  /// An internal list of inouts to this [Module].
  final Map<String, Logic> _inOuts = {};

  /// The parent [Module] of this [Module].
  ///
  /// This only gets populated after its parent [Module], if it exists, has
  /// been built.
  Module? get parent => _parent;

  /// A cached copy of the parent, useful for debug and efficiency
  Module? _parent;

  /// A map from [input] port names to this [Module] to corresponding [Logic]
  /// signals.
  @protected
  Map<String, Logic> get inputs => UnmodifiableMapView<String, Logic>(_inputs);

  /// A map from [output] port names to this [Module] to corresponding [Logic]
  /// signals.
  Map<String, Logic> get outputs =>
      UnmodifiableMapView<String, Logic>(_outputs);

  @protected //TODO
  Map<String, Logic> get inOuts => UnmodifiableMapView<String, Logic>(_inOuts);

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
  late final Iterable<Logic> signals = CombinedListView([
    UnmodifiableListView(_inputs.values),
    UnmodifiableListView(_outputs.values),
    UnmodifiableListView(_inOuts.values),
    UnmodifiableListView(internalSignals),
  ]);

  /// Accesses the [Logic] associated with this [Module]s input port
  /// named [name].
  ///
  /// Only logic within this [Module] should consume this signal.
  @protected
  Logic input(String name) => _inputs.containsKey(name)
      ? _inputs[name]!
      : throw PortDoesNotExistException(
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
      : throw PortDoesNotExistException(
          'Output name "$name" not found as an output of this Module.');

  @protected //TODO: should this be protected or is it like output?  i think yes like input
  Logic inOut(String name) => _inOuts.containsKey(name)
      ? _inOuts[name]!
      : throw PortDoesNotExistException(
          'InOut name "$name" not found as an in/out of this Module.');

  //TODO: doc
  //TODO: test
  @protected
  Logic? tryInOut(String name) => _inOuts[name];

  /// Provides the [output] named [name] if it exists, otherwise `null`.
  Logic? tryOutput(String name) => _outputs[name];

  /// Returns true iff [signal] is the same [Logic] as the [input] port of this
  /// [Module] with the same name.
  bool isInput(Logic signal) =>
      _inputs[signal.name] == signal ||
      (signal.isArrayMember && isInput(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as the [output] port of this
  /// [Module] with the same name.
  bool isOutput(Logic signal) =>
      _outputs[signal.name] == signal ||
      (signal.isArrayMember && isOutput(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as the [inOut] port of this
  /// [Module] with the same name.
  bool isInOut(Logic signal) =>
      _inOuts[signal.name] == signal ||
      (signal.isArrayMember && isInOut(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as an [input], [output], or
  /// [inOut] port of this [Module] with the same name.
  bool isPort(Logic signal) =>
      isInput(signal) || isOutput(signal) || isInOut(signal);

  /// If this module has a [parent], after [build] this will be a guaranteed
  /// unique name within its scope.
  String get uniqueInstanceName => hasBuilt || reserveName
      ? _uniqueInstanceName
      : throw ModuleNotBuiltException(
          'Module must be built to access uniquified name.'
          '  Call build() before accessing this.');
  String _uniqueInstanceName;

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
      : _uniqueInstanceName =
            Naming.validatedName(name, reserveName: reserveName) ?? name,
        _definitionName = Naming.validatedName(definitionName,
            reserveName: reserveDefinitionName);

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

  /// Indicates whether this [Module] has had the [build] method called on it.
  bool get hasBuilt => _hasBuilt;
  bool _hasBuilt = false;

  /// Builds the [Module] and all [subModules] within it.
  ///
  /// It is recommended not to override [build] nor put logic in [build]
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
    for (final output in [..._outputs.values, ...inOuts.values]) {
      await _traceOutputForModuleContents(output, dontAddSignal: true);
    }
    // 2) trace from inputs of all modules to inputs of this module
    for (final input in [..._inputs.values, ...inOuts.values]) {
      await _traceInputForModuleContents(input, dontAddSignal: true);
    }

    // set unique module instance names for submodules
    final uniquifier = Uniquifier();
    for (final module in _modules) {
      module._uniqueInstanceName = uniquifier.getUniqueName(
          initialName: Sanitizer.sanitizeSV(module.name),
          reserved: module.reserveName);
    }

    //TODO: assert that no modules contain each other
    //TODO: check benchmarks on perf hit for this, should be low
    assert(
      _moduleSelfContainmentCheck(this),
      'No module should contain itself.',
    );

    _hasBuilt = true;

    ModuleTree.rootModuleInstance = this;
  }

  //TODO: doc
  static bool _moduleSelfContainmentCheck(Module module) {
    //TODO: test this method?

    final mods = TraverseableCollection<Module>()..add(module);

    for (var i = 0; i < mods.length; i++) {
      final mod = mods[i];

      for (final subMod in mod.subModules) {
        if (mods.contains(subMod)) {
          return false;
        }

        mods.add(mod);
      }
    }

    return true;
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
  @Deprecated('Use `Naming.unpreferredName` or `Logic.naming` instead.')
  @protected
  static String unpreferredName(String name) => Naming.unpreferredName(name);

  /// Returns true iff the signal name is "unpreferred".
  ///
  /// See documentation for [unpreferredName] for more details.
  @Deprecated('Use `Naming.isUnpreferred` or `Logic.naming` instead.')
  static bool isUnpreferred(String name) => Naming.isUnpreferred(name);

//TODO BUG: not finding sub-modules in arrays for connections between net arrays (often)

  /// Searches for [Logic]s and [Module]s within this [Module] from its inputs.
  Future<void> _traceInputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isOutput(signal) || _inOutDrivers.contains(signal)) {
      return;
    }

    //TODO: can we go back?
    if (!signal.isPort && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    // if (_hasParsedFromInput.contains(signal)) {
    //   return;
    // }
    // _hasParsedFromInput.add(signal);

    if (signal is LogicStructure && !isPort(signal)) {
      for (final subSignal in signal.elements) {
        await _traceInputForModuleContents(subSignal);
      }
    }

    final subModule =
        (signal.isInput || signal.isInOut) ? signal.parentModule : null;

    final subModuleParent = subModule?.parent;

    if (!dontAddSignal && signal.isOutput) {
      // somehow we have reached the output of a module which is not a submodule
      // nor this module, bad!
      throw Exception('Violation of input/output rules in $this on $signal.'
          '  Logic within a Module should only consume inputs and drive outputs'
          ' of that Module.'
          '  See https://intel.github.io/rohd-website/docs/modules/'
          ' for more information.');
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

      for (final subModuleInOutDriver in [
        ...subModule._inOutDrivers,
      ]) {
        await _traceInputForModuleContents(subModuleInOutDriver);
        await _traceOutputForModuleContents(subModuleInOutDriver);
      }
    } else {
      if (!dontAddSignal &&
          !isInput(signal) &&
          !isInOut(signal) &&
          subModule == null) {
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

        // TODO this seems over-the-top, is there a better way?
        // maybe a function in NetConnect that lets you find the "other" one would be good
        if (isInOut(signal) &&
            dstConnection.parentModule is NetConnect &&
            dstConnection.parentModule!._inOuts.values
                .map((e) => e.srcConnections)
                .flattened
                .where(_inOutDrivers.contains)
                .isNotEmpty) {
          // if this is a NetConnect crossing the module boundary, don't trace
          continue;
        }

        await _traceInputForModuleContents(dstConnection);
      }

      //TODO: is this needed?
      // if (signal.isNet) {
      //   for (final srcConnection
      //       in signal.srcConnections.where((element) => element.isNet)) {
      //     await _traceInputForModuleContents(srcConnection);
      //     await _traceOutputForModuleContents(srcConnection);
      //   }
      //   for (final dstConnection
      //       in signal.dstConnections.where((element) => element.isNet)) {
      //     await _traceInputForModuleContents(dstConnection);
      //     await _traceOutputForModuleContents(dstConnection);
      //   }
      // }
    }
  }

  //TODO: these shouldnt need to be split
  final Set<Logic> _hasParsedFromInput = {};
  final Set<Logic> _hasParsedFromOutput = {};

  /// Searches for [Logic]s and [Module]s within this [Module] from its outputs.
  Future<void> _traceOutputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isInput(signal) || _inOutDrivers.contains(signal)) {
      return;
    }

    //TODO: can we go back to this method of parent module determination?
    if (!signal.isPort && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    // if (_hasParsedFromOutput.contains(signal)) {
    //   return;
    // }
    // _hasParsedFromOutput.add(signal);

    if (signal is LogicStructure && !isPort(signal)) {
      for (final subSignal in signal.elements) {
        await _traceOutputForModuleContents(subSignal);
      }
    }

    final subModule =
        (signal.isOutput || signal.isInOut) ? signal.parentModule : null;

    final subModuleParent = subModule?.parent;

    if (!dontAddSignal && signal.isInput) {
      // somehow we have reached the input of a module which is not a submodule
      // nor this module, bad!
      //TODO: update this message and docs about inouts!
      throw Exception('Violation of input/output rules in $this on $signal.'
          '  Logic within a Module should only consume inputs and drive outputs'
          ' of that Module.'
          '  See https://intel.github.io/rohd-website/docs/modules/'
          ' for more information.');
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

      for (final subModuleInOutDriver in [
        ...subModule._inOutDrivers,
      ]) {
        await _traceInputForModuleContents(subModuleInOutDriver);
        await _traceOutputForModuleContents(subModuleInOutDriver);
      }
    } else {
      if (!dontAddSignal &&
          !isOutput(signal) &&
          !isInOut(signal) &&
          subModule == null) {
        _addInternalSignal(signal);
        for (final dstConnection in signal.dstConnections) {
          await _traceInputForModuleContents(dstConnection);
        }
      }

      //TODO: is this needed?
      // if (signal.isNet && !isPort(signal)) {
      //   for (final srcConnection
      //       in signal.srcConnections.where((element) => element.isNet)) {
      //     await _traceOutputForModuleContents(srcConnection);
      //     await _traceInputForModuleContents(srcConnection);
      //   }
      //   for (final dstConnection
      //       in signal.dstConnections.where((element) => element.isNet)) {
      //     //TODO: why not all dst?
      //     await _traceOutputForModuleContents(dstConnection);
      //     await _traceInputForModuleContents(dstConnection);
      //   }
      // }

      // TODO: why can't we just always iterate across all srcConnections here?
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

    if (signal.isArrayMember) {
      _addInternalSignal(signal.parentStructure!);
    }

    // ignore: invalid_use_of_protected_member
    signal.parentModule = this;
  }

  /// Checks whether a port name is safe to add (e.g. no duplicates).
  void _checkForSafePortName(String name) {
    Naming.validatedName(name, reserveName: true);

    if (outputs.containsKey(name) ||
        inputs.containsKey(name) ||
        inOuts.containsKey(name)) {
      throw UnavailableReservedNameException.withMessage(
          'Already defined a port with name "$name".');
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

    final inPort = Logic(name: name, width: width, naming: Naming.reserved)
      ..gets(x)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _inputs[name] = inPort;

    return inPort;
  }

  /// TODO
  /// A set of signals that drive [inOut]s from *outside* this [Module].
  final Set<Logic> _inOutDrivers = {};

  //TODO: is it important that `x` here is a LogicNet? what about for arrays?
  // TODO: the `x` must be the port to the *outside* world, and the returned
  //  signal from `addInOut` or `inOut` is what should be used inside!
  @protected
  LogicNet addInOut(String name, Logic x, {int width = 1}) {
    _checkForSafePortName(name);
    if (x.width != width) {
      throw PortWidthMismatchException(x, width);
    }

    //TODO: is x really necessary?
    // how can we tell if an inout is being driven from inside or outside of a module???
    // maybe we can trust that build() finds the *first* driver of it as external and then sets parentModule correctly?

    _inOutDrivers.add(x);

    final inOutPort =
        LogicNet(name: name, width: width, naming: Naming.reserved)
          // ignore: invalid_use_of_protected_member
          ..parentModule = this
          ..gets(x);

    _inOuts[name] = inOutPort;

    return inOutPort;
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

    final inArr = LogicArray(
      name: name,
      dimensions,
      elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
      naming: Naming.reserved,
    )
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

    final outPort = Logic(name: name, width: width, naming: Naming.reserved)
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

    final outArr = LogicArray(
      name: name,
      dimensions,
      elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
      naming: Naming.reserved,
    )
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _outputs[name] = outArr;

    return outArr;
  }

  // TODO test
  // TODO doc
  @protected
  LogicArray addInOutArray(
    String name,
    Logic x, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _checkForSafePortName(name);

    // make sure we register all the _inOutDrivers properly
    final xElems = [x];
    for (var i = 0; i < xElems.length; i++) {
      final xi = xElems[i];
      _inOutDrivers.add(xi);
      if (xi is LogicArray) {
        xElems.addAll(xi.elements);
      }
    }

    final inOutArr = LogicArray.net(
      name: name,
      dimensions,
      elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
      naming: Naming.reserved,
    )
      ..gets(x)
      // ignore: invalid_use_of_protected_member
      ..parentModule = this;

    _inOuts[name] = inOutArr;

    return inOutArr;
  }

  @override
  String toString() => '"$name" ($runtimeType)  :'
      '  ${_inputs.keys} => ${_outputs.keys}; ${_inOuts.keys}';

  /// Returns a pretty-print [String] of the heirarchy of all [Module]s within
  /// this [Module].
  String hierarchyString([int indent = 0]) {
    final padding = List.filled(indent, '  ').join();
    final hier = StringBuffer('$padding> ${toString()}');

    //TODO TEMP
    hier.writeln();
    for (final s in inputs.values) {
      hier.writeln('$padding>-  in: \t$s');
    }
    for (final s in outputs.values) {
      hier.writeln('$padding>-  out:\t$s');
    }
    for (final s in inOuts.values) {
      hier.writeln('$padding>-  inout:\t$s');
    }
    for (final s in internalSignals) {
      hier.writeln('$padding>-  internal:\t$s');
    }

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

// extension _ModuleLogicStructureUtils on LogicStructure {
//   /// Provides a list of all source connections of all elements within
//   /// this structure, recursively.
//   ///
//   /// Useful for searching during [Module] build.
//   Iterable<Logic> get srcConnections => [
//         for (final element in elements)
//           if (element is LogicStructure)
//             ...element.srcConnections
//           else if (element.srcConnection != null)
//             element.srcConnection!
//       ];
// }
