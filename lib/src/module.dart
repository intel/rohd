// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module.dart
// Definition for abstract module class.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:collection';

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

  /// An internal collection of sub-modules.
  final TraverseableCollection<Module> _subModules = TraverseableCollection();

  /// An internal collection of internal signals.
  final TraverseableCollection<Logic> _internalSignals =
      TraverseableCollection();

  /// An internal mapping of inputs to this [Module].
  late final Map<String, Logic> _inputs = {};

  /// An internal mapping of outputs to this [Module].
  late final Map<String, Logic> _outputs = {};

  /// An internal mapping of inOuts to this [Module].
  late final Map<String, Logic> _inOuts = {};

  /// An internal mapping of input names to their sources to this [Module].
  late final Map<String, Logic> _inputSources = {};

  /// An internal mapping of inOut names to their sources to this [Module].
  late final Map<String, Logic> _inOutSources = {};

  /// The parent [Module] of this [Module].
  ///
  /// This only gets populated after its parent [Module], if it exists, has
  /// been built.
  Module? get parent => _parent;

  /// A cached copy of the parent, useful for debug and efficiency
  Module? _parent;

  /// A map from [input] port names to this [Module] to corresponding [Logic]
  /// signals.
  ///
  /// Note that [inputs] should only be used to drive hardware *within* a
  /// [Module]. To access the signal that drives these inputs, use
  /// [inputSource].
  Map<String, Logic> get inputs => UnmodifiableMapView<String, Logic>(_inputs);

  /// A map from [output] port names to this [Module] to corresponding [Logic]
  /// signals.
  Map<String, Logic> get outputs =>
      UnmodifiableMapView<String, Logic>(_outputs);

  /// A map from [inOut] port names to this [Module] to corresponding [Logic]
  /// signals.
  ///
  /// Note that [inOuts] should only be used for hardware *within* a [Module].
  /// To access the signal that drives/received these inOuts from outside of
  /// this [Module], use [inOutSource].
  Map<String, Logic> get inOuts => UnmodifiableMapView<String, Logic>(_inOuts);

  /// An [Iterable] of all [Module]s contained within this [Module].
  ///
  /// This only gets populated after this [Module] has been built.
  Iterable<Module> get subModules =>
      UnmodifiableTraverseableCollectionView<Module>(_subModules);

  /// An [Iterable] of all [Logic]s contained within this [Module] which are
  /// *not* an input or output port of this [Module].
  ///
  /// This does not contain any signals within [subModules].
  Iterable<Logic> get internalSignals =>
      UnmodifiableTraverseableCollectionView<Logic>(_internalSignals);

  /// An [Iterable] of all [Logic]s contained within this [Module], including
  /// inputs, outputs, and internal signals of this [Module].
  ///
  /// This does not contain any signals within [subModules].
  Iterable<Logic> get signals => UnmodifiableListView([
        ..._inputs.values,
        ..._outputs.values,
        ..._inOuts.values,
        ...internalSignals,
      ]);

  /// Accesses the [Logic] associated with this [Module]s [input] port
  /// named [name].
  ///
  /// Only logic within this [Module] should consume this signal.
  Logic input(String name) => _inputs.containsKey(name)
      ? _inputs[name]!
      : throw PortDoesNotExistException(
          'Input name "$name" not found as an input to this Module.');

  /// The original `source` provided to the creation of the [input] port [name]
  /// via [addInput] or [addInputArray].
  Logic inputSource(String name) =>
      _inputSources[name] ??
      (throw PortDoesNotExistException(
          '$name is not an input of this Module.'));

  /// Provides the [input] named [name] if it exists, otherwise `null`.
  ///
  /// Only logic within this [Module] should consume this signal.
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

  /// Provides the [output] named [name] if it exists, otherwise `null`.
  Logic? tryOutput(String name) => _outputs[name];

  /// Accesses the [Logic] associated with this [Module]s inOut port
  /// named [name].
  ///
  /// Only logic within this [Module] should consume this signal.
  Logic inOut(String name) => _inOuts.containsKey(name)
      ? _inOuts[name]!
      : throw PortDoesNotExistException(
          'InOut name "$name" not found as an in/out of this Module.');

  /// The original `source` provided to the creation of the [inOut] port [name]
  /// via [addInOut] or [addInOutArray].
  Logic inOutSource(String name) =>
      _inOutSources[name] ??
      (throw PortDoesNotExistException(
          '$name is not an inOut of this Module.'));

  /// Provides the [inOut] named [name] if it exists, otherwise `null`.
  Logic? tryInOut(String name) => _inOuts[name];

  /// Returns true iff [signal] is the same [Logic] as the [input] port of this
  /// [Module] with the same name.
  ///
  /// Note that if signal is a [LogicStructure] which contains an [input] port,
  /// but is not itself a port, this will return false.
  bool isInput(Logic signal) =>
      _inputs[signal.name] == signal ||
      (signal.parentStructure != null && isInput(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as the [output] port of this
  /// [Module] with the same name.
  ///
  /// Note that if signal is a [LogicStructure] which contains an [output] port,
  /// but is not itself a port, this will return false.
  bool isOutput(Logic signal) =>
      _outputs[signal.name] == signal ||
      (signal.parentStructure != null && isOutput(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as the [inOut] port of this
  /// [Module] with the same name.
  ///
  /// Note that if signal is a [LogicStructure] which contains an [inOut] port,
  /// but is not itself a port, this will return false.
  bool isInOut(Logic signal) =>
      _inOuts[signal.name] == signal ||
      (signal.parentStructure != null && isInOut(signal.parentStructure!));

  /// Returns true iff [signal] is the same [Logic] as an [input], [output], or
  /// [inOut] port of this [Module] with the same name.
  bool isPort(Logic signal) =>
      isInput(signal) || isOutput(signal) || isInOut(signal);

  /// If this module has a [parent], after [build] this will be a guaranteed
  /// unique name within its scope.
  String get uniqueInstanceName => hasBuilt || reserveName
      ? _uniqueInstanceName
      : throw ModuleNotBuiltException(
          this, 'Module must be built to access uniquified name.');
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
          this, 'Module must be built before accessing hierarchy.');
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
    for (final module in _subModules) {
      module._uniqueInstanceName = uniquifier.getUniqueName(
          initialName: Sanitizer.sanitizeSV(module.name),
          reserved: module.reserveName);
    }

    _checkValidHierarchy(visited: {});

    _hasBuilt = true;

    ModuleTree.rootModuleInstance = this;
  }

  /// Confirms that the post-[build] hierarchy is valid.
  ///
  /// - No module exists in two separate hierarchies.
  /// - No module is a submodule of itself.
  void _checkValidHierarchy({
    required Map<Module, List<Module>> visited,
    List<Module> hierarchy = const [],
  }) {
    final newHierarchy = [...hierarchy, this];

    if (hierarchy.contains(this)) {
      final loopHierarchy = _hierarchyListToString(newHierarchy);
      throw InvalidHierarchyException(
          'Module $this is a submodule of itself: $loopHierarchy');
    }

    if (visited.containsKey(this)) {
      final otherHierarchy = _hierarchyListToString(visited[this]!);
      final thisHierarchy = _hierarchyListToString(hierarchy);
      throw InvalidHierarchyException(
          'Module $this exists at more than one hierarchy: '
          '$otherHierarchy and $thisHierarchy');
    }

    visited[this] = newHierarchy;

    for (final subModule in subModules) {
      subModule._checkValidHierarchy(visited: visited, hierarchy: newHierarchy);
    }
  }

  /// Converts a [hierarchy] (like used in [_checkValidHierarchy]) into a string
  /// that can be used for error messages.
  static String _hierarchyListToString(List<Module> hierarchy) =>
      hierarchy.map((e) => e.name).join('.');

  /// Adds a [Module] to this as a subModule.
  Future<void> _addAndBuildModule(Module module) async {
    if (module.parent != null) {
      throw Exception('This Module "$this" already has a parent. '
          'If you are hitting this as a user of ROHD, please file '
          'a bug at https://github.com/intel/rohd/issues.');
    }

    _subModules.add(module);

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

  /// Searches for [Logic]s and [Module]s within this [Module] from its inputs.
  Future<void> _traceInputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isOutput(signal) || _inOutDrivers.contains(signal)) {
      return;
    }

    if (!signal.isPort && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    try {
      final subModule =
          (signal.isInput || signal.isInOut) ? signal.parentModule : null;

      final subModuleParent = subModule?.parent;

      if (!dontAddSignal && signal.isOutput) {
        // somehow we have reached the output of a module which is not a
        // submodule nor this module, bad!
        throw PortRulesViolationException(this, signal.toString());
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

        for (final subModuleInOutDriver in subModule._inOutDrivers) {
          final subModDontAddSignal = subModuleInOutDriver.isPort;
          await _traceInputForModuleContents(subModuleInOutDriver,
              dontAddSignal: subModDontAddSignal);
          await _traceOutputForModuleContents(subModuleInOutDriver,
              dontAddSignal: subModDontAddSignal);
        }
      } else {
        if (!dontAddSignal &&
            !isInput(signal) &&
            !isInOut(signal) &&
            subModule == null) {
          _addInternalSignal(signal);

          // handle expanding the search for arrays
          if (signal.parentStructure != null) {
            await _traceInputForModuleContents(signal.parentStructure!,
                dontAddSignal: signal.isPort);
            await _traceOutputForModuleContents(signal.parentStructure!,
                dontAddSignal: signal.isPort);
          }
          if (signal is LogicStructure) {
            for (final elem in signal.elements) {
              await _traceInputForModuleContents(elem,
                  dontAddSignal: elem.isPort);
              await _traceOutputForModuleContents(elem,
                  dontAddSignal: elem.isPort);
            }
          }

          for (final srcConnection in signal.srcConnections) {
            await _traceOutputForModuleContents(srcConnection);
          }
        }

        if (!dontAddSignal && isInput(signal)) {
          throw PortRulesViolationException(
              this,
              signal.name,
              'Input $signal of module $this is dependent on'
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

        // extra searching in both directions for nets
        if (signal.isNet && !isPort(signal)) {
          await _traceOutputForModuleContents(signal);
          for (final srcConnection
              in signal.srcConnections.where((element) => element.isNet)) {
            await _traceInputForModuleContents(srcConnection);
            await _traceOutputForModuleContents(srcConnection);
          }
          for (final dstConnection
              in signal.dstConnections.where((element) => element.isNet)) {
            await _traceInputForModuleContents(dstConnection);
            await _traceOutputForModuleContents(dstConnection);
          }
        }
      }
    } on PortRulesViolationException catch (e) {
      throw PortRulesViolationException.trace(
          module: this,
          signal: signal,
          lowerException: e,
          traceDirection: 'from inputs');
    }
  }

  /// Searches for [Logic]s and [Module]s within this [Module] from its outputs.
  Future<void> _traceOutputForModuleContents(Logic signal,
      {bool dontAddSignal = false}) async {
    if (isInput(signal) || _inOutDrivers.contains(signal)) {
      return;
    }

    if (!signal.isPort && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    try {
      final subModule =
          (signal.isOutput || signal.isInOut) ? signal.parentModule : null;

      final subModuleParent = subModule?.parent;

      if (!dontAddSignal && signal.isInput) {
        // somehow we have reached the input of a module which is not a
        // submodule nor this module, bad!
        throw PortRulesViolationException(this, signal.toString());
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

        for (final subModuleInOutDriver in subModule._inOutDrivers) {
          final subModDontAddSignal = subModuleInOutDriver.isPort;
          await _traceInputForModuleContents(subModuleInOutDriver,
              dontAddSignal: subModDontAddSignal);
          await _traceOutputForModuleContents(subModuleInOutDriver,
              dontAddSignal: subModDontAddSignal);
        }
      } else {
        if (!dontAddSignal &&
            !isOutput(signal) &&
            !isInOut(signal) &&
            subModule == null) {
          _addInternalSignal(signal);

          // handle expanding the search for arrays
          if (signal.parentStructure != null) {
            await _traceOutputForModuleContents(signal.parentStructure!,
                dontAddSignal: signal.isPort);
            await _traceInputForModuleContents(signal.parentStructure!,
                dontAddSignal: signal.isPort);
          }
          if (signal is LogicStructure) {
            for (final elem in signal.elements) {
              await _traceOutputForModuleContents(elem,
                  dontAddSignal: elem.isPort);
              await _traceInputForModuleContents(elem,
                  dontAddSignal: elem.isPort);
            }
          }

          for (final dstConnection in signal.dstConnections) {
            await _traceInputForModuleContents(dstConnection);
          }
        }

        // extra searching in both directions for nets
        if (signal.isNet && !isPort(signal)) {
          await _traceInputForModuleContents(signal);
          for (final srcConnection
              in signal.srcConnections.where((element) => element.isNet)) {
            await _traceOutputForModuleContents(srcConnection);
            await _traceInputForModuleContents(srcConnection);
          }
          for (final dstConnection
              in signal.dstConnections.where((element) => element.isNet)) {
            await _traceOutputForModuleContents(dstConnection);
            await _traceInputForModuleContents(dstConnection);
          }
        }

        if (signal is LogicStructure) {
          for (final elem in signal.elements) {
            await _traceOutputForModuleContents(elem,
                dontAddSignal: elem.isPort);
          }
        } else {
          for (final srcConnection in signal.srcConnections) {
            await _traceOutputForModuleContents(srcConnection);
          }
        }
      }
    } on PortRulesViolationException catch (e) {
      throw PortRulesViolationException.trace(
          module: this,
          signal: signal,
          lowerException: e,
          traceDirection: 'from outputs');
    }
  }

  /// Registers a signal as an internal signal.
  void _addInternalSignal(Logic signal) {
    assert(!signal.isPort, 'Should not be adding a port as an internal signal');

    _internalSignals.add(signal);

    signal.parentModule = this;
  }

  /// Checks whether a port name is safe to add (e.g. no duplicates).
  void _checkForSafePortName(String name) {
    Naming.validatedName(name, reserveName: true);

    if (outputs.containsKey(name) ||
        inputs.containsKey(name) ||
        inOuts.containsKey(name)) {
      throw UnavailableReservedNameException.withMessage(
          'Already defined a port with name "$name" in module "${this.name}".');
    }
  }

  /// Registers a signal as an [input] to this [Module] and returns an [input]
  /// port that can be consumed.
  ///
  /// The return value is the same as what is returned by [input] and should
  /// only be used within this [Module]. The provided [source] is accessible via
  /// [inputSource].
  Logic addInput(String name, Logic source, {int width = 1}) {
    _checkForSafePortName(name);
    if (source.width != width) {
      throw PortWidthMismatchException(source, width);
    }

    if (source is LogicStructure) {
      // ignore: parameter_assignments
      source = source.packed;
    }

    final inPort = Logic(name: name, width: width, naming: Naming.reserved)
      ..gets(source)
      ..parentModule = this;

    _inputs[name] = inPort;

    _inputSources[name] = source;

    return inPort;
  }

  /// Registers a signal as an [input] to this [Module] and returns an [input]
  /// port that can be consumed. The type of the port will be [LogicType] and
  /// constructed via [Logic.clone], so it is required that the [source]
  /// implements clone functionality that matches the type and properly updates
  /// the [Logic.name] as well.
  ///
  /// This is a good way to construct [input]s that have matching widths or
  /// dimensions to their [source] signal, or to make a [LogicStructure] an
  /// [input]. You can use this on a [Logic], [LogicArray], or [LogicStructure].
  ///
  /// The [source] cannot be or contain any [LogicNet]s. If [source] is a
  /// [Const] (or is a [LogicStructure] that includes a [Const]), the
  /// [LogicType] must be set to [Logic], since [Const]s cannot be driven and
  /// are not suitable as ports.
  ///
  /// The return value is the same as what is returned by [input] and should
  /// only be used within this [Module]. The provided [source] is accessible via
  /// [inputSource].
  LogicType addTypedInput<LogicType extends Logic>(
      String name, LogicType source) {
    _checkForSafePortName(name);

    // ignore: parameter_assignments
    source = _validateType<LogicType>(source, isOutput: false, name: name);

    if (source.isNet || (source is LogicStructure && source.hasNets)) {
      throw PortTypeException(source, 'Typed inputs cannot have nets in them.');
    }

    final inPort = (source.clone(name: name) as LogicType)..gets(source);

    if (inPort.name != name) {
      throw PortTypeException.forIntendedName(name,
          'The `clone` method for $source failed to update the signal name.');
    }

    if (inPort is LogicStructure) {
      inPort.setAllParentModule(this);
    } else {
      inPort.parentModule = this;
    }

    _inputs[name] = inPort;

    _inputSources[name] = source;

    return inPort;
  }

  /// A set of signals that drive [inOut]s from *outside* this [Module].
  ///
  /// This is necessary to keep track when tracing since these are
  /// bidirectional.
  final Set<Logic> _inOutDrivers = {};

  /// Registers a signal as an [inOut] to this [Module] and returns an [inOut]
  /// port that can be consumed inside this [Module].
  ///
  /// The return value is the same as what is returned by [inOut] and should
  /// only be used within this [Module]. The provided [source] is accessible via
  /// [inOutSource].
  LogicNet addInOut(String name, Logic source, {int width = 1}) {
    _checkForSafePortName(name);
    if (source.width != width) {
      throw PortWidthMismatchException(source, width);
    }

    _inOutDrivers.add(source);

    // we need to properly detect all inout sources, even for arrays
    if (source.isArrayMember || source is LogicArray) {
      final sourceElems = TraverseableCollection<Logic>()..add(source);
      for (var i = 0; i < sourceElems.length; i++) {
        final sei = sourceElems[i];
        _inOutDrivers.add(sei);

        if (sei.isArrayMember) {
          sourceElems.add(sei.parentStructure!);
        }

        if (sei is LogicArray) {
          sourceElems.addAll(sei.elements);
        }
      }
    }

    if (source is LogicStructure) {
      // need to also track the packed version if it's a structure, since the
      // signal that's actually getting connected to the port *is* the packed
      // one, not the original array/struct.
      _inOutDrivers.add(source.packed);
    }

    final inOutPort =
        LogicNet(name: name, width: width, naming: Naming.reserved)
          ..parentModule = this
          ..gets(source);

    _inOuts[name] = inOutPort;

    _inOutSources[name] = source;

    return inOutPort;
  }

  /// Registers a signal as an [inOut] to this [Module] and returns an [inOut]
  /// port that can be consumed inside this [Module]. The type of the port will
  /// be [LogicType] and constructed via [Logic.clone], so it is required that
  /// the [source] implements clone functionality that matches the type and
  /// properly updates the [Logic.name] as well.
  ///
  /// This is a good way to construct [inOut]s that have matching widths or
  /// dimensions to their [source] signal, or to make a [LogicStructure] an
  /// [inOut]. You can use this on a [Logic], [LogicArray], or [LogicStructure].
  ///
  /// The [source] must be or exclusively contain [LogicNet]s. If [source] is a
  /// [Const] (or is a [LogicStructure] that includes a [Const]), the
  /// [LogicType] must be set to [Logic], since [Const]s cannot be driven and
  /// are not suitable as ports.
  ///
  /// The return value is the same as what is returned by [inOut] and should
  /// only be used within this [Module]. The provided [source] is accessible via
  /// [inOutSource].
  LogicType addTypedInOut<LogicType extends Logic>(
      String name, LogicType source) {
    _checkForSafePortName(name);

    if (!source.isNet) {
      throw PortTypeException(source, 'Typed inOuts must be nets.');
    }

    // ignore: parameter_assignments
    source = _validateType<LogicType>(source, isOutput: false, name: name);

    _inOutDrivers.add(source);

    // we need to properly detect all inout sources
    if (source is LogicStructure) {
      final sourceElems = TraverseableCollection<Logic>()..add(source);
      for (var i = 0; i < sourceElems.length; i++) {
        final sei = sourceElems[i];
        _inOutDrivers.add(sei);

        if (sei.parentStructure != null) {
          sourceElems.add(sei.parentStructure!);
        }

        if (sei is LogicStructure) {
          sourceElems.addAll(sei.elements);
        }
      }
    }

    final inOutPort = (source.clone(name: name) as LogicType)..gets(source);

    if (inOutPort.name != name) {
      throw PortTypeException.forIntendedName(name,
          'The `clone` method for $source failed to update the signal name.');
    }

    if (inOutPort is LogicStructure) {
      inOutPort.setAllParentModule(this);
    } else {
      inOutPort.parentModule = this;
    }

    _inOutDrivers.addAll(inOutPort.srcConnections);

    _inOuts[name] = inOutPort;

    _inOutSources[name] = source;

    return inOutPort;
  }

  /// Registers and returns an [input] [LogicArray] port to this [Module] with
  /// the specified [dimensions], [elementWidth], and [numUnpackedDimensions]
  /// named [name].
  ///
  /// This is very similar to [addInput], except for [LogicArray]s.
  ///
  /// Performs validation on overall width matching for [source], but not on
  /// [dimensions], [elementWidth], or [numUnpackedDimensions].
  LogicArray addInputArray(
    String name,
    Logic source, {
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
      ..gets(source)
      ..setAllParentModule(this);

    _inputs[name] = inArr;

    _inputSources[name] = source;

    return inArr;
  }

  /// Registers an [output] to this [Module] and returns an [output] port that
  /// can be driven by this [Module] or consumed outside of it.
  ///
  /// The return value is the same as what is returned by [output].
  Logic addOutput(String name, {int width = 1}) {
    _checkForSafePortName(name);

    final outPort = Logic(name: name, width: width, naming: Naming.reserved)
      ..parentModule = this;

    _outputs[name] = outPort;

    return outPort;
  }

  /// Checks that the [logic] meets type requirements for `Typed` [Logic]s and
  /// returns a potentially modified [logic] to use.
  LogicType _validateType<LogicType extends Logic>(LogicType logic,
      {required String name, required bool isOutput}) {
    const exceptionMessage =
        'Cannot use `Const` (or `LogicStructure` with `Const`s) as a port type.'
        ' Try passing in a `Logic` or parameterizing'
        ' using `<Logic>` explicitly instead.';

    if (LogicType == Const) {
      throw PortTypeException(logic, exceptionMessage);
    }

    if (logic is Const || (logic is LogicStructure && logic.hasConsts)) {
      if (LogicType == Logic) {
        // we're ok, can just convert to Logic
        final newLogic =
            Logic(name: name, width: logic.width, naming: Naming.mergeable)
                as LogicType;
        if (isOutput) {
          return newLogic;
        } else {
          return newLogic..gets(logic);
        }
      } else {
        throw PortTypeException(logic, exceptionMessage);
      }
    }

    return logic;
  }

  /// Registers an [output] to this [Module] and returns an [output] port that
  /// can be driven by this [Module] or consumed outside of it. The type of the
  /// port will be [LogicType] and constructed via [logicGenerator], which must
  /// properly update the `name` of the generated [LogicType] as well.
  ///
  /// This is a good way to construct [output]s that have matching widths or
  /// dimensions to another signal, or to make a [LogicStructure] an [output].
  /// You can use this on a [Logic], [LogicArray], or [LogicStructure].
  ///
  /// The [logicGenerator] cannot create ports that are or contain any
  /// [LogicNet]s in them. If a [Const] is generated (or included in a
  /// [LogicStructure]), the [LogicType] must be set to [Logic], since [Const]s
  /// cannot be driven and are not suitable as ports.
  ///
  /// The return value is the same as what is returned by [output].
  LogicType addTypedOutput<LogicType extends Logic>(
      String name, LogicType Function({String name}) logicGenerator) {
    _checkForSafePortName(name);

    // must make a new clone of it, to avoid people using ports of other modules
    var outPort = logicGenerator(name: name);

    outPort = _validateType<LogicType>(outPort, isOutput: true, name: name);

    if (outPort.isNet || (outPort is LogicStructure && outPort.hasNets)) {
      throw PortTypeException(
          outPort, 'Typed outputs cannot have nets in them.');
    }

    if (outPort.name != name) {
      throw PortTypeException.forIntendedName(
          name,
          'The `logicGenerator` function failed to'
          ' update the signal name on $outPort.');
    }

    if (outPort is LogicStructure) {
      outPort.setAllParentModule(this);
    } else {
      outPort.parentModule = this;
    }

    _outputs[name] = outPort;

    return outPort;
  }

  /// Registers and returns an [output] [LogicArray] port to this [Module] with
  /// the specified [dimensions], [elementWidth], and [numUnpackedDimensions]
  /// named [name].
  ///
  /// This is very similar to [addOutput], except for [LogicArray]s.
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
    )..setAllParentModule(this);

    _outputs[name] = outArr;

    return outArr;
  }

  /// Registers and returns an [inOut] [LogicArray] port to this [Module] with
  /// the specified [dimensions], [elementWidth], and [numUnpackedDimensions]
  /// named [name].
  ///
  /// This is very similar to [addInOut], except for [LogicArray]s.
  ///
  /// Performs validation on overall width matching for [source], but not on
  /// [dimensions], [elementWidth], or [numUnpackedDimensions].
  LogicArray addInOutArray(
    String name,
    Logic source, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _checkForSafePortName(name);

    // make sure we register all the _inOutDrivers properly
    final sourceElems = TraverseableCollection<Logic>()..add(source);
    for (var i = 0; i < sourceElems.length; i++) {
      final sei = sourceElems[i];
      _inOutDrivers.add(sei);

      if (sei.isArrayMember) {
        sourceElems.add(sei.parentStructure!);
      }

      if (sei is LogicArray) {
        sourceElems.addAll(sei.elements);
      }
    }

    final inOutArr = LogicArray.net(
      name: name,
      dimensions,
      elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
      naming: Naming.reserved,
    )
      ..gets(source)
      ..setAllParentModule(this);

    // there may be packed arrays created by the `gets` above, so this makes
    // sure we catch all of those.
    _inOutDrivers.addAll(inOutArr.srcConnections);

    _inOuts[name] = inOutArr;

    _inOutSources[name] = source;

    return inOutArr;
  }

  /// Connects the [source] to this [Module] using [Interface.connectIO] and
  /// returns a copy of the [source] that can be used within this module.
  InterfaceType addInterfacePorts<InterfaceType extends Interface<TagType>,
              TagType extends Enum>(InterfaceType source,
          {Iterable<TagType>? inputTags,
          Iterable<TagType>? outputTags,
          Iterable<TagType>? inOutTags,
          String Function(String original)? uniquify}) =>
      (source.clone() as InterfaceType)
        ..connectIO(this, source,
            inputTags: inputTags,
            outputTags: outputTags,
            inOutTags: inOutTags,
            uniquify: uniquify);

  /// Connects the [source] to this [Module] using [PairInterface.pairConnectIO]
  /// and returns a copy of the [source] that can be used within this module.
  InterfaceType addPairInterfacePorts<InterfaceType extends PairInterface>(
          InterfaceType source, PairRole role,
          {String Function(String original)? uniquify}) =>
      (source.clone() as InterfaceType)
        ..pairConnectIO(this, source, role, uniquify: uniquify);

  @override
  String toString() => [
        '"$name" ($definitionName)  : ',
        if (_inputs.isNotEmpty) '${_inputs.keys}',
        if (_outputs.isNotEmpty) '=> ${_outputs.keys}',
        if (_inOuts.isNotEmpty) '; ${_inOuts.keys}'
      ].join(' ');

  /// Returns a pretty-print [String] of the heirarchy of all [Module]s within
  /// this [Module].
  String hierarchyString([int indent = 0]) {
    final padding = List.filled(indent, '  ').join();
    final hier = StringBuffer('$padding> ${toString()}');

    for (final module in _subModules) {
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
      throw ModuleNotBuiltException(this);
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
            .getSynthFileContents()
            .join('\n\n////////////////////\n\n');
  }
}

extension on LogicStructure {
  /// Indicates that a [LogicStructure] has a [Const] element within it or
  /// within one of its [elements].
  bool get hasConsts =>
      elements.any((e) => e is Const || (e is LogicStructure && e.hasConsts));
}
