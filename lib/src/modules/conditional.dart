// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional.dart
// Definitions of conditionallly executed hardware constructs (if/else statements, always_comb, always_ff, etc.)
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/duplicate_detection_set.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/exceptions/conditionals/conditional_exceptions.dart';
import 'package:rohd/src/exceptions/module/port_width_mismatch_exception.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/synchronous_propagator.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a block of logic, similar to `always` blocks in SystemVerilog.
abstract class _Always extends Module with CustomSystemVerilog {
  /// A [List] of the [Conditional]s to execute.
  List<Conditional> get conditionals =>
      UnmodifiableListView<Conditional>(_conditionals);
  late List<Conditional> _conditionals;

  /// A mapping from internal receiver signals to designated [Module] outputs.
  final Map<Logic, Logic> _assignedReceiverToOutputMap =
      HashMap<Logic, Logic>();

  /// A mapping from internal driver signals to designated [Module] inputs.
  final Map<Logic, Logic> _assignedDriverToInputMap = HashMap<Logic, Logic>();

  final Uniquifier _portUniquifier = Uniquifier();

  /// Executes provided [conditionals] at the appropriate time (specified by
  /// child class).
  ///
  /// If [reset] is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high.
  /// The default reset value is to `0`, but if [resetValues] is provided then
  /// the corresponding value associated with the driven signal will be set to
  /// that value instead upon reset. If a signal is in [resetValues] but not
  /// driven by any other [Conditional] in this block, it will be driven to the
  /// specified reset value.
  _Always(this._conditionals,
      {Logic? reset, Map<Logic, dynamic>? resetValues, super.name = 'always'}) {
    // create a registration of all inputs and outputs of this module
    var idx = 0;

    // Get all Receivers
    final allReceivers =
        conditionals.map((e) => e.receivers).expand((e) => e).toSet();

    // This will reset the conditionals on setting the `reset` flag
    if (reset != null) {
      final allResetCondAssigns = <Conditional>[];
      final signalsBeingReset = <Logic>{};

      if (resetValues != null) {
        final toConsiderForElementsReset = <Logic>[
          ...resetValues.keys,
        ];

        for (var i = 0; i < toConsiderForElementsReset.length; i++) {
          final toConsider = toConsiderForElementsReset[i];

          // if it's a structure, we need to consider its elements
          if (toConsider is LogicStructure) {
            toConsiderForElementsReset.addAll(toConsider.elements);
          }

          // if we're already resetting this signal, flag an issue
          if (signalsBeingReset.contains(toConsider)) {
            throw SignalRedrivenException([toConsider],
                'Signal is already being reset by another reset value: ');
          }

          if (resetValues.containsKey(toConsider)) {
            // should only be true for top-level structures referenced
            allResetCondAssigns.add(toConsider < resetValues[toConsider]);
          }

          // always add the signal, even if this is a sub-element
          signalsBeingReset.add(toConsider);
        }
      }

      // now add the reset to 0 for all the remaining ones
      for (final receiver in allReceivers.toList()) {
        if (!signalsBeingReset.contains(receiver)) {
          allResetCondAssigns.add(receiver < 0);
        }
      }

      _conditionals = [
        // If resetValue for a receiver is defined,
        If(
          reset,
          // then use it for assigning receiver
          then: allResetCondAssigns,
          // else assign zero as resetValue
          orElse: conditionals,
        ),
      ];
    }

    for (final conditional in conditionals) {
      for (final driver in conditional.drivers) {
        if (!_assignedDriverToInputMap.containsKey(driver)) {
          final inputName = _portUniquifier.getUniqueName(
              initialName: Module.unpreferredName(
                  Sanitizer.sanitizeSV('in${idx}_${driver.name}')));
          addInput(inputName, driver, width: driver.width);
          _assignedDriverToInputMap[driver] = input(inputName);
          idx++;
        }
      }
      for (final receiver in conditional.receivers) {
        if (!_assignedReceiverToOutputMap.containsKey(receiver)) {
          final outputName = _portUniquifier.getUniqueName(
              initialName: Module.unpreferredName(
                  Sanitizer.sanitizeSV('out${idx}_${receiver.name}')));
          addOutput(outputName, width: receiver.width);
          _assignedReceiverToOutputMap[receiver] = output(outputName);
          receiver <= output(outputName);
          idx++;
        }
      }

      // share the registration information down
      conditional._updateAssignmentMaps(
          _assignedReceiverToOutputMap, _assignedDriverToInputMap);
    }
  }

  String _alwaysContents(Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final contents = StringBuffer();
    for (final conditional in conditionals) {
      final subContents = conditional.verilogContents(
          1, inputsNameMap, outputsNameMap, assignOperator);
      contents.write('$subContents\n');
    }
    return contents.toString();
  }

  /// The "always" part of the `always` block when generating SystemVerilog.
  ///
  /// For example, `always_comb` or `always_ff`.
  @protected
  String alwaysVerilogStatement(Map<String, String> inputs);

  /// The assignment operator to use when generating SystemVerilog.
  ///
  /// For example `=` or `<=`.
  @protected
  String assignOperator();

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    var verilog = '';
    verilog += '//  $instanceName\n';
    verilog += '${alwaysVerilogStatement(inputs)} begin\n';
    verilog += _alwaysContents(inputs, outputs, assignOperator());
    verilog += 'end\n';
    return verilog;
  }
}

/// A signal that represents an SSA node in [Combinational.ssa] which is
/// associated with one specific [Combinational].
class _SsaLogic extends Logic {
  /// The signal that this represents.
  final Logic _ref;

  /// A unique identifier for the context of which [Combinational.ssa] it is
  /// associated with.
  final int _context;

  /// Constructs a new SSA node referring to a signal in a specific context.
  _SsaLogic(this._ref, this._context)
      : super(width: _ref.width, name: _ref.name);
}

/// Represents a block of combinational logic.
///
/// This is similar to an `always_comb` block in SystemVerilog.
class Combinational extends _Always {
  /// Constructs a new [Combinational] which executes [conditionals] in order
  /// procedurally.
  ///
  /// If any "write after read" occurs, then a [WriteAfterReadException] will
  /// be thrown since it could lead to a mismatch between simulation and
  /// synthesis.  See [Combinational.ssa] for more details.
  Combinational(super.conditionals, {super.name = 'combinational'}) {
    _execute(); // for initial values
    for (final driver in _assignedDriverToInputMap.keys) {
      driver.glitch.listen((args) {
        _execute();
      });
    }
  }

  /// An internal counter to keep track of unique contexts
  /// per [Combinational.ssa].
  static int _ssaContextCounter = 0;

  /// Constructs a new [Combinational] where [construct] generates a list of
  /// [Conditional]s which use the provided remapping function to enable
  /// a "static single-asssignment" (SSA) form for procedural execution. The
  /// Wikipedia article has a good explanation:
  /// https://en.wikipedia.org/wiki/Static_single-assignment_form
  ///
  /// In SystemVerilog, an `always_comb` block can easily produce
  /// non-synthesizable or ambiguous design blocks which can lead to subtle
  /// bugs and mismatches between simulation and synthesis.  Since
  /// [Combinational] maps directly to an `always_comb` block, it is also
  /// susceptible to these types of issues in the path to synthesis.
  ///
  /// A large class of  these issues can be prevented by avoiding a "write after
  /// read" scenario, where a signal is assigned a value after that value would
  /// have had an impact on prior procedural assignment in that same
  /// [Combinational] execution.
  ///
  /// [Combinational.ssa] remaps signals such that signals are only "written"
  /// once.
  ///
  /// The below example shows a simple use case:
  /// ```dart
  /// Combinational.ssa((s) => [
  ///   s(y) < 1,
  ///   s(y) < s(y) + 1,
  /// ]);
  /// ```
  ///
  /// Note that every variable in this case must be "initialized" before it
  /// can be used.
  ///
  /// Note that signals returned by the remapping function (`s`) are tied to
  /// this specific instance of [Combinational] and shouldn't be used elsewhere
  /// or you may see unexpected behavior.  Also note that each instance of
  /// signal returned by the remapping function should be used in at most
  /// one [Conditional] and on either the receiving or driving side, but not
  /// both.  These restrictions are generally easy to adhere to unless you do
  /// something strange.
  ///
  /// There is a construction-time performance penalty for usage of this
  /// roughly proportional to the size of the design feeding into this instance.
  /// This is because it must search for any remapped signals along the entire
  /// combinational and sequential path feeding into each [Conditional].  This
  /// penalty is purely at generation time, not in simulation or the actual
  /// generated design.  For very large designs, this penalty can be
  /// mitigated by constructing the [Combinational.ssa] before connecting
  /// inputs to the rest of the design, but usually the impact is so small
  /// that it will not be noticeable.
  factory Combinational.ssa(
      List<Conditional> Function(Logic Function(Logic signal) s) construct,
      {String name = 'combinational_ssa'}) {
    final context = _ssaContextCounter++;

    Logic getSsa(Logic ref) => _SsaLogic(ref, context);

    final conditionals = construct(getSsa);

    _processSsa(conditionals, context: context);

    return Combinational(conditionals, name: name);
  }

  /// Executes the remapping for all the [conditionals] recursively.
  static void _processSsa(List<Conditional> conditionals,
      {required int context}) {
    var mappings = <Logic, Logic>{};
    for (final conditional in conditionals) {
      mappings = conditional._processSsa(mappings, context: context);
    }

    for (final mapping in mappings.entries) {
      if (mapping.key.srcConnection != null) {
        throw MappedSignalAlreadyAssignedException(mapping.key.name);
      }

      mapping.key <= mapping.value;
    }
  }

  /// Keeps track of whether this block is already mid-execution, in order to
  /// detect reentrance.
  bool _isExecuting = false;

  /// Keeps track of already-driven logics during [_execute].
  ///
  /// Must be cleared at the end of each [_execute].
  final Set<Logic> _drivenLogics = HashSet<Logic>();

  /// Keeps track of signals already [_guard]ed.
  ///
  /// Must be cleared at the end of each [_execute].
  final Set<Logic> _guarded = HashSet<Logic>();

  /// Keeps track of subscriptions to glitches for each of the [_guarded].
  ///
  /// Must be cleared at the end of each [_execute].
  final List<SynchronousSubscription<LogicValueChanged>> _guardListeners =
      <SynchronousSubscription<LogicValueChanged>>[];

  /// A function that sub-[Conditional]s should call to guard signals they
  /// are consuming.
  void _guard(Logic toGuard) {
    if (_guarded.add(toGuard)) {
      _guardListeners.add(toGuard.glitch.listen(_writeAfterRead));
    }
  }

  /// A function that throws a [WriteAfterReadException].
  ///
  /// Declared as a separate static function so that it doesn't need to be
  /// created on each [_guard] call.
  static void _writeAfterRead(args) {
    throw WriteAfterReadException();
  }

  /// Performs the functional behavior of this block.
  void _execute() {
    if (_isExecuting) {
      // this combinational is already executing, which means an input has
      // changed as a result of some output of this combinational changing.
      // this is imperative style, so don't loop
      return;
    }

    _isExecuting = true;

    for (final element in conditionals) {
      element.execute(_drivenLogics, _guard);
    }

    // combinational must always drive all outputs or else you get X!
    if (_assignedReceiverToOutputMap.length != _drivenLogics.length) {
      for (final receiverOutputPair in _assignedReceiverToOutputMap.entries) {
        if (!_drivenLogics.contains(receiverOutputPair.key)) {
          receiverOutputPair.value.put(LogicValue.x, fill: true);
        }
      }
    }

    // clean up after execution
    for (final guardListener in _guardListeners) {
      guardListener.cancel();
    }
    _guardListeners.clear();
    _drivenLogics.clear();
    _guarded.clear();

    _isExecuting = false;
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) => 'always_comb';
  @override
  String assignOperator() => '=';
}

/// Deprecated: use [Sequential] instead.
@Deprecated('Use Sequential instead')
typedef FF = Sequential;

/// Represents a block of sequential logic.
///
/// This is similar to an `always_ff` block in SystemVerilog.  Positive edge
/// triggered by either one trigger or multiple with [Sequential.multi].
class Sequential extends _Always {
  /// The input clocks used in this block.
  final List<Logic> _clks = [];

  /// Constructs a [Sequential] single-triggered by [clk].
  ///
  /// If `reset` is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high.
  /// The default reset value is to `0`, but if `resetValues` is provided then
  /// the corresponding value associated with the driven signal will be set to
  /// that value instead upon reset. If a signal is in `resetValues` but not
  /// driven by any other [Conditional] in this block, it will be driven to the
  /// specified reset value.
  Sequential(Logic clk, List<Conditional> conditionals,
      {Logic? reset,
      Map<Logic, dynamic>? resetValues,
      String name = 'sequential'})
      : this.multi([clk], conditionals,
            name: name, reset: reset, resetValues: resetValues);

  /// Constructs a [Sequential] multi-triggered by any of [clks].
  ///
  /// If `reset` is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high.
  /// The default reset value is to `0`, but if `resetValues` is provided then
  /// the corresponding value associated with the driven signal will be set to
  /// that value instead upon reset. If a signal is in `resetValues` but not
  /// driven by any other [Conditional] in this block, it will be driven to the
  /// specified reset value.
  Sequential.multi(List<Logic> clks, super.conditionals,
      {super.reset, super.resetValues, super.name = 'sequential'}) {
    for (var i = 0; i < clks.length; i++) {
      final clk = clks[i];
      if (clk.width > 1) {
        throw Exception('Each clk must be 1 bit, but saw $clk.');
      }
      _clks.add(addInput(
          _portUniquifier.getUniqueName(
              initialName: Sanitizer.sanitizeSV(
                  Module.unpreferredName('clk${i}_${clk.name}'))),
          clk));
      _preTickClkValues.add(null);
    }
    _setup();
  }

  /// A map from input [Logic]s to the values that should be used for
  /// computations on the edge.
  final Map<Logic, LogicValue> _inputToPreTickInputValuesMap =
      HashMap<Logic, LogicValue>();

  /// The value of the clock before the tick.
  final List<LogicValue?> _preTickClkValues = [];

  /// Keeps track of whether the clock has glitched and an [_execute] is
  /// necessary.
  bool _pendingExecute = false;

  /// A set of drivers whose values in [_inputToPreTickInputValuesMap] need
  /// updating after the tick completes.
  final Set<Logic> _driverInputsPendingPostUpdate = {};

  /// Keeps track of whether values need to be updated post-tick.
  bool _pendingPostUpdate = false;

  /// Performs setup steps for custom functional behavior of this block.
  void _setup() {
    // one time is enough, it's a final map
    for (final element in conditionals) {
      element._updateOverrideMap(_inputToPreTickInputValuesMap);
    }

    // listen to every input of this `Sequential` for changes
    for (final driverInput in _assignedDriverToInputMap.values) {
      // pre-fill the _inputToPreTickInputValuesMap so that nothing ever
      // uses values directly
      _inputToPreTickInputValuesMap[driverInput] = driverInput.value;

      driverInput.glitch.listen((event) async {
        if (Simulator.phase != SimulatorPhase.clkStable) {
          // if the change happens not when the clocks are stable, immediately
          // update the map
          _inputToPreTickInputValuesMap[driverInput] = driverInput.value;
        } else {
          // if this is during stable clocks, it's probably another flop
          // driving it, so hold onto it for later
          _driverInputsPendingPostUpdate.add(driverInput);
          if (!_pendingPostUpdate) {
            unawaited(
              Simulator.postTick.first.then(
                (value) {
                  // once the tick has completed,
                  // we can update the override maps
                  for (final driverInput in _driverInputsPendingPostUpdate) {
                    _inputToPreTickInputValuesMap[driverInput] =
                        driverInput.value;
                  }
                  _driverInputsPendingPostUpdate.clear();
                  _pendingPostUpdate = false;
                },
              ).catchError(
                test: (error) => error is Exception,
                // ignore: avoid_types_on_closure_parameters
                (Object err, StackTrace stackTrace) {
                  Simulator.throwException(err as Exception, stackTrace);
                },
              ),
            );
          }
          _pendingPostUpdate = true;
        }
      });
    }

    // listen to every clock glitch to see if we need to execute
    for (var i = 0; i < _clks.length; i++) {
      final clk = _clks[i];
      clk.glitch.listen((event) async {
        // we want the first previousValue from the first glitch of this tick
        _preTickClkValues[i] ??= event.previousValue;
        if (!_pendingExecute) {
          unawaited(Simulator.clkStable.first.then((value) {
            // once the clocks are stable, execute the contents of the FF
            _execute();
            _pendingExecute = false;
          }).catchError(test: (error) => error is Exception,
              // ignore: avoid_types_on_closure_parameters
              (Object err, StackTrace stackTrace) {
            Simulator.throwException(err as Exception, stackTrace);
          }).catchError(test: (error) => error is StateError,
              // ignore: avoid_types_on_closure_parameters
              (Object err, StackTrace stackTrace) {
            // This could be a result of the `Simulator` being reset, causing
            // the stream to `close` before `first` occurs.
            if (!Simulator.simulationHasEnded) {
              // If the `Simulator` is still running, rethrow immediately.

              // ignore: only_throw_errors
              throw err;
            }
          }));
        }
        _pendingExecute = true;
      });
    }
  }

  void _execute() {
    var anyClkInvalid = false;
    var anyClkPosedge = false;

    for (var i = 0; i < _clks.length; i++) {
      // if the pre-tick value is null, then it should have the same value as
      // it currently does
      if (!_clks[i].value.isValid || !(_preTickClkValues[i]?.isValid ?? true)) {
        anyClkInvalid = true;
        break;
      } else if (_preTickClkValues[i] != null &&
          LogicValue.isPosedge(_preTickClkValues[i]!, _clks[i].value)) {
        anyClkPosedge = true;
        break;
      }
    }

    if (anyClkInvalid) {
      for (final receiverOutput in _assignedReceiverToOutputMap.values) {
        receiverOutput.put(LogicValue.x);
      }
    } else if (anyClkPosedge) {
      final allDrivenSignals = DuplicateDetectionSet<Logic>();
      for (final element in conditionals) {
        element.execute(allDrivenSignals, null);
      }
      if (allDrivenSignals.hasDuplicates) {
        throw SignalRedrivenException(allDrivenSignals.duplicates);
      }
    }

    // clear out all the pre-tick value of clocks
    for (var i = 0; i < _clks.length; i++) {
      _preTickClkValues[i] = null;
    }
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) {
    final triggers =
        _clks.map((clk) => 'posedge ${inputs[clk.name]}').join(' or ');
    return 'always_ff @($triggers)';
  }

  @override
  String assignOperator() => '<=';
}

/// Represents an some logical assignments or actions that will only happen
/// under certain conditions.
abstract class Conditional {
  /// A [Map] from receiver [Logic] signals passed into this [Conditional] to
  /// the appropriate output logic port.
  late Map<Logic, Logic> _assignedReceiverToOutputMap;

  /// A [Map] from driver [Logic] signals passed into this [Conditional] to
  /// the appropriate input logic port.
  late Map<Logic, Logic> _assignedDriverToInputMap;

  /// A [Map] of override [LogicValue]s for driver [Logic]s of
  /// this [Conditional].
  ///
  /// This is used for things like [Sequential]'s pre-tick values.
  Map<Logic, LogicValue> _driverValueOverrideMap = {};

  /// Updates the values of [_assignedReceiverToOutputMap] and
  /// [_assignedDriverToInputMap] and passes them down to all
  /// sub-[Conditional]s as well.
  void _updateAssignmentMaps(
    Map<Logic, Logic> assignedReceiverToOutputMap,
    Map<Logic, Logic> assignedDriverToInputMap,
  ) {
    _assignedReceiverToOutputMap = assignedReceiverToOutputMap;
    _assignedDriverToInputMap = assignedDriverToInputMap;
    for (final conditional in conditionals) {
      conditional._updateAssignmentMaps(
          assignedReceiverToOutputMap, assignedDriverToInputMap);
    }
  }

  /// Updates the value of [_driverValueOverrideMap] and passes it down to all
  /// sub-[Conditional]s as well.
  void _updateOverrideMap(Map<Logic, LogicValue> driverValueOverrideMap) {
    // this is for always_ff pre-tick values
    _driverValueOverrideMap = driverValueOverrideMap;
    for (final conditional in conditionals) {
      conditional._updateOverrideMap(driverValueOverrideMap);
    }
  }

  /// Gets the value that should be used for execution for the input port
  /// associated with [driver].
  @protected
  LogicValue driverValue(Logic driver) =>
      _driverValueOverrideMap[driverInput(driver)] ??
      _assignedDriverToInputMap[driver]!.value;

  /// Gets the input port associated with [driver].
  @protected
  Logic driverInput(Logic driver) => _assignedDriverToInputMap[driver]!;

  /// Gets the output port associated with [receiver].
  @protected
  Logic receiverOutput(Logic receiver) =>
      _assignedReceiverToOutputMap[receiver]!;

  /// Executes the functionality of this [Conditional] and
  /// populates [drivenSignals] with all [Logic]s that were driven
  /// during execution.
  ///
  /// The [drivenSignals] are used by the caller to determine if signals
  /// were driven an appropriate number of times.
  ///
  /// The [guard] function should be called on drivers *prior* to any execution
  /// which consumes the current value of those drivers.  It is used to check
  /// that signals are not "written after read", for example.
  @protected
  void execute(Set<Logic> drivenSignals, void Function(Logic toGuard)? guard);

  /// Lists *all* receivers, recursively including all sub-[Conditional]s
  /// receivers.
  @Deprecated('Use `receivers` instead.')
  List<Logic> getReceivers() => receivers;

  /// The same as [receivers], but uncached for situations where the list of
  /// [conditionals] may still be modified or to compute the cached result
  /// for [receivers] itself.
  List<Logic> _getReceivers();

  /// Lists *all* receivers, recursively including all sub-[Conditional]s
  /// receivers.
  List<Logic> get receivers;

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  @Deprecated('Use `drivers` instead.')
  List<Logic> getDrivers() => drivers;

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  List<Logic> get drivers;

  /// Lists of *all* [Conditional]s directly contained within this [Conditional]
  /// (not including itself).
  ///
  /// Does *not* recursively call down through sub-[Conditional]s.
  @Deprecated('Use `conditionals` instead.')
  List<Conditional> getConditionals() => conditionals;

  /// Lists of *all* [Conditional]s directly contained within this [Conditional]
  /// (not including itself).
  ///
  /// Does *not* recursively call down through sub-[Conditional]s.
  List<Conditional> get conditionals;

  /// Returns a [String] of SystemVerilog to be used in generated output.
  ///
  /// The [indent] is used for pretty-printing, and should generally be
  /// incremented for sub-[Conditional]s. The [inputsNameMap] and
  /// [outputsNameMap] are a mapping from port names to SystemVerilog variable
  /// names for inputs and outputs, respectively.  The [assignOperator] is the
  /// SystemVerilog operator that should be used for any assignments within
  /// this [Conditional].
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator);

  /// Calculates an amount of padding to provie at the beginning of each new
  /// line based on [indent].
  static String calcPadding(int indent) => List.filled(indent, '  ').join();

  /// Connects [driver] to drive all appropriate SSA nodes based on [mappings]
  /// which match the provided [context].
  static void _connectSsaDriverFromMappings(
      Logic driver, Map<Logic, Logic> mappings,
      {required int context}) {
    final ssaDrivers = Conditional._findSsaDriversFrom(driver, context);

    // take all the "current" names for these signals
    for (final ssaDriver in ssaDrivers) {
      if (!mappings.containsKey(ssaDriver._ref)) {
        throw UninitializedSignalException(ssaDriver._ref.name);
      }

      // if these are already connected, just skip it, we're fine already
      if (ssaDriver.srcConnection != null &&
          ssaDriver.srcConnection == mappings[ssaDriver._ref]!) {
        continue;
      }

      // if these are the same signal, also just skip it
      if (ssaDriver == mappings[ssaDriver._ref]!) {
        continue;
      }

      ssaDriver <= mappings[ssaDriver._ref]!;
    }
  }

  /// Searches for SSA nodes from a source [driver] which match the [context].
  static List<_SsaLogic> _findSsaDriversFrom(Logic driver, int context) {
    final toParse = TraverseableCollection<Logic>()..add(driver);
    final foundSsaLogics = <_SsaLogic>{};
    for (var i = 0; i < toParse.length; i++) {
      if (toParse[i].srcConnection != null) {
        toParse.add(toParse[i].srcConnection!);
      }
      if (toParse[i].isOutput) {
        toParse.addAll(toParse[i].parentModule!.inputs.values);
      }
      if (toParse[i] is _SsaLogic &&
          (toParse[i] as _SsaLogic)._context == context) {
        foundSsaLogics.add(toParse[i] as _SsaLogic);
      }
    }

    return foundSsaLogics.toList(growable: false);
  }

  /// Given existing [currentMappings], connects [drivers] and [receivers]
  /// accordingly to [_SsaLogic]s and returns an updated set of mappings.
  ///
  /// This function may add new [Conditional]s to existing [Conditional]s.
  ///
  /// This is used for [Combinational.ssa].
  Map<Logic, Logic> _processSsa(Map<Logic, Logic> currentMappings,
      {required int context});
}

/// Represents a group of [Conditional]s to be executed.
class ConditionalGroup extends Conditional {
  @override
  final List<Conditional> conditionals;

  /// Creates a group of [conditionals] to be executed in order and bundles
  /// them into a single [Conditional].
  ConditionalGroup(this.conditionals);

  @override
  Map<Logic, Logic> _processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    var mappings = currentMappings;
    for (final conditional in conditionals) {
      mappings = conditional._processSsa(mappings, context: context);
    }
    return mappings;
  }

  @override
  late final List<Logic> drivers = [
    for (final conditional in conditionals) ...conditional.drivers
  ];

  @override
  late final List<Logic> receivers = _getReceivers();

  @override
  List<Logic> _getReceivers() =>
      [for (final conditional in conditionals) ...conditional.receivers];

  @override
  void execute(Set<Logic> drivenSignals, void Function(Logic toGuard)? guard) {
    for (final conditional in conditionals) {
      conditional.execute(drivenSignals, guard);
    }
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
          Map<String, String> outputsNameMap, String assignOperator) =>
      conditionals
          .map((c) => c.verilogContents(
                indent,
                inputsNameMap,
                outputsNameMap,
                assignOperator,
              ))
          .join('\n');
}

/// An assignment that only happens under certain conditions.
///
/// [Logic] has a short-hand for creating [ConditionalAssign] via the
///  `<` operator.
class ConditionalAssign extends Conditional {
  /// The input to this assignment.
  final Logic receiver;

  /// The output of this assignment.
  final Logic driver;

  /// Conditionally assigns [receiver] to the value of [driver].
  ConditionalAssign(this.receiver, this.driver) {
    if (driver.width != receiver.width) {
      throw PortWidthMismatchException.equalWidth(receiver, driver);
    }
  }

  @override
  String toString() => '${receiver.name} < ${driver.name}';

  @override
  late final List<Logic> receivers = [receiver];

  @override
  List<Logic> _getReceivers() => receivers;

  @override
  late final List<Logic> drivers = [driver];

  @override
  late final List<Conditional> conditionals = const [];

  /// A cached copy of the result of [receiverOutput] to save on lookups.
  late final _receiverOutput = receiverOutput(receiver);

  @override
  void execute(Set<Logic> drivenSignals,
      [void Function(Logic toGuard)? guard]) {
    if (guard != null) {
      guard(driver);
    }

    _receiverOutput.put(driverValue(driver));

    if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
      drivenSignals.add(receiver);
    }
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final driverName = inputsNameMap[driverInput(driver).name]!;
    final receiverName = outputsNameMap[receiverOutput(receiver).name]!;
    return '$padding$receiverName $assignOperator $driverName;';
  }

  @override
  Map<Logic, Logic> _processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    Conditional._connectSsaDriverFromMappings(driver, currentMappings,
        context: context);

    final newMappings = <Logic, Logic>{...currentMappings};
    // if the receiver is an ssa node, then update the mapping
    if (receiver is _SsaLogic) {
      newMappings[(receiver as _SsaLogic)._ref] = receiver;
    }

    return newMappings;
  }
}

/// Represents a single case within a [Case] block.
class CaseItem {
  /// The value to match against.
  final Logic value;

  /// A [List] of [Conditional]s to execute when [value] is matched.
  final List<Conditional> then;

  /// Executes [then] when [value] matches.
  CaseItem(this.value, this.then);

  @override
  String toString() => '$value : $then';
}

/// Controls characteristics about [Case] blocks.
///
/// The default type is [none].  The [unique] and [priority] values have
/// behavior similar to what is implemented in SystemVerilog.
///
/// [priority] indicates that the decisions must be executed in the same order
/// that they are listed, and that every legal scenario is included.
/// An exception will be thrown if there is no match to a scenario.
///
/// [unique] indicates that for a given expression, only one item will match.
/// If multiple items match the expression, an exception will be thrown.
/// If there is no match and no default item, an exception will also be thrown.
enum ConditionalType {
  /// There are no special checking or expectations.
  none,

  /// Expect that exactly one condition is true.
  unique,

  /// Expect that at least one condition is true, and the first one is executed.
  priority
}

/// A block of [CaseItem]s where only the one with a matching [CaseItem.value]
/// is executed.
///
/// Searches for which of [items] appropriately matches [expression], then
/// executes the matching [CaseItem].  If [defaultItem] is specified, and no
/// other item matches, then that one is executed.  Use [conditionalType] to
/// modify behavior in ways similar to what is available in SystemVerilog.
class Case extends Conditional {
  /// A logical signal to match against.
  final Logic expression;

  /// An ordered collection of [CaseItem]s to search through for a match
  /// to [expression].
  final List<CaseItem> items;

  /// The default to execute when there was no match with any other [CaseItem]s.
  List<Conditional>? get defaultItem => _defaultItem;
  List<Conditional>? _defaultItem;

  /// The type of case block this is, for special attributes
  /// (e.g. [ConditionalType.unique], [ConditionalType.priority]).
  ///
  /// See [ConditionalType] for more details.
  final ConditionalType conditionalType;

  /// Whenever an item in [items] matches [expression], it will be executed.
  ///
  /// If none of [items] match, then [defaultItem] is executed.
  Case(this.expression, this.items,
      {List<Conditional>? defaultItem,
      this.conditionalType = ConditionalType.none})
      : _defaultItem = defaultItem {
    for (final item in items) {
      if (item.value.width != expression.width) {
        throw PortWidthMismatchException.equalWidth(expression, item.value);
      }
    }
  }

  /// Returns true iff [value] matches the expressions current value.
  @protected
  bool isMatch(LogicValue value, LogicValue expressionValue) =>
      expressionValue == value;

  /// Returns the SystemVerilog keyword to represent this case block.
  @protected
  String get caseType => 'case';

  @override
  void execute(Set<Logic> drivenSignals, [void Function(Logic)? guard]) {
    if (guard != null) {
      guard(expression);
      for (final item in items) {
        guard(item.value);
      }
    }

    if (!expression.value.isValid) {
      // if expression has X or Z, then propogate X's!
      for (final receiver in receivers) {
        receiverOutput(receiver).put(LogicValue.x);
        if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
          drivenSignals.add(receiver);
        }
      }
      return;
    }

    CaseItem? foundMatch;

    for (final item in items) {
      // match on the first matchinig item
      if (isMatch(driverValue(item.value), driverValue(expression))) {
        for (final conditional in item.then) {
          conditional.execute(drivenSignals, guard);
        }
        if (foundMatch != null && conditionalType == ConditionalType.unique) {
          throw Exception('Unique case statement had multiple matching cases.'
              ' Original: "$foundMatch".'
              ' Duplicate: "$item".');
        }

        foundMatch = item;

        if (conditionalType != ConditionalType.unique) {
          break;
        }
      }
    }

    // no items matched
    if (foundMatch == null && defaultItem != null) {
      for (final conditional in defaultItem!) {
        conditional.execute(drivenSignals, guard);
      }
    } else if (foundMatch == null &&
        (conditionalType == ConditionalType.unique ||
            conditionalType == ConditionalType.priority)) {
      throw Exception('$conditionalType case statement had no matching case,'
          ' and type was $conditionalType.');
    }
  }

  @override
  late final List<Conditional> conditionals =
      UnmodifiableListView(_getConditionals());

  /// Calculates the set of conditionals directly within this.
  List<Conditional> _getConditionals() => [
        ...items.map((item) => item.then).expand((conditional) => conditional),
        if (defaultItem != null) ...defaultItem!
      ];

  @override
  late final List<Logic> drivers = _getDrivers();

  /// Calculates the set of drivers recursively down.
  List<Logic> _getDrivers() {
    final drivers = <Logic>[expression];
    for (final item in items) {
      drivers
        ..add(item.value)
        ..addAll(item.then
            .map((conditional) => conditional.drivers)
            .expand((driver) => driver)
            .toList(growable: false));
    }
    if (defaultItem != null) {
      drivers.addAll(defaultItem!
          .map((conditional) => conditional.drivers)
          .expand((driver) => driver)
          .toList(growable: false));
    }
    return drivers;
  }

  @override
  late final List<Logic> receivers = _getReceivers();

  @override
  List<Logic> _getReceivers() {
    final receivers = <Logic>[];
    for (final item in items) {
      receivers.addAll(item.then
          .map((conditional) => conditional.receivers)
          .flattened
          .toList(growable: false));
    }
    if (defaultItem != null) {
      receivers.addAll(defaultItem!
          .map((conditional) => conditional.receivers)
          .flattened
          .toList(growable: false));
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final expressionName = inputsNameMap[driverInput(expression).name];
    var caseHeader = caseType;
    if (conditionalType == ConditionalType.priority) {
      caseHeader = 'priority $caseType';
    } else if (conditionalType == ConditionalType.unique) {
      caseHeader = 'unique $caseType';
    }
    final verilog = StringBuffer('$padding$caseHeader ($expressionName) \n');
    final subPadding = Conditional.calcPadding(indent + 2);
    for (final item in items) {
      final conditionName = inputsNameMap[driverInput(item.value).name];
      final caseContents = item.then
          .map((conditional) => conditional.verilogContents(
              indent + 4, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      verilog.write('''
$subPadding$conditionName : begin
$caseContents
${subPadding}end
''');
    }
    if (defaultItem != null) {
      final defaultCaseContents = defaultItem!
          .map((conditional) => conditional.verilogContents(
              indent + 4, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      verilog.write('''
${subPadding}default : begin
$defaultCaseContents
${subPadding}end
''');
    }
    verilog.write('${padding}endcase\n');

    return verilog.toString();
  }

  @override
  Map<Logic, Logic> _processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    // add an empty default if there isn't already one, since we need it for phi
    _defaultItem ??= [];

    // first connect direct drivers into the case statement
    Conditional._connectSsaDriverFromMappings(expression, currentMappings,
        context: context);
    for (final itemDriver in items.map((e) => e.value)) {
      Conditional._connectSsaDriverFromMappings(itemDriver, currentMappings,
          context: context);
    }

    // calculate mappings locally within each item
    final phiMappings = <Logic, Logic>{};
    for (final conditionals in [
      ...items.map((e) => e.then),
      defaultItem!,
    ]) {
      var localMappings = {...currentMappings};

      for (final conditional in conditionals) {
        localMappings =
            conditional._processSsa(localMappings, context: context);
      }

      for (final localMapping in localMappings.entries) {
        if (!phiMappings.containsKey(localMapping.key)) {
          phiMappings[localMapping.key] = Logic(
            name: '${localMapping.key.name}_phi',
            width: localMapping.key.width,
          );
        }

        conditionals.add(phiMappings[localMapping.key]! < localMapping.value);
      }
    }

    final newMappings = <Logic, Logic>{...currentMappings}..addAll(phiMappings);

    // find all the SSA signals that are driven by anything in this case block,
    // since we need to ensure every case drives them or else we may create
    // an inferred latch
    final signalsNeedingInit = [
      ...items.map((e) => e.then).flattened,
      ...defaultItem!,
    ].map((e) => e._getReceivers()).flattened.whereType<_SsaLogic>().toSet();
    for (final conditionals in [
      ...items.map((e) => e.then),
      defaultItem!,
    ]) {
      final alreadyDrivenSsaSignals = conditionals
          .map((e) => e._getReceivers())
          .flattened
          .whereType<_SsaLogic>()
          .toSet();

      for (final signalNeedingInit in signalsNeedingInit) {
        if (!alreadyDrivenSsaSignals.contains(signalNeedingInit)) {
          conditionals.add(signalNeedingInit < 0);
        }
      }
    }

    return newMappings;
  }
}

/// A special version of [Case] which can do wildcard matching via `z` in
/// the expression.
///
/// Any `z` in the value of a [CaseItem] will act as a wildcard.
///
/// Does not support SystemVerilog's `?` syntax, which is exactly functionally
/// equivalent to `z` syntax.
class CaseZ extends Case {
  /// Whenever an item in [items] matches [expression], it will be executed, but
  /// the definition of matches allows for `z` to be a wildcard.
  ///
  /// If none of [items] match, then [defaultItem] is executed.
  CaseZ(super.expression, super.items,
      {super.defaultItem, super.conditionalType});

  @override
  String get caseType => 'casez';

  @override
  bool isMatch(LogicValue value, LogicValue expressionValue) {
    for (var i = 0; i < expression.width; i++) {
      if (expressionValue[i] != value[i] && value[i] != LogicValue.z) {
        return false;
      }
    }
    return true;
  }
}

/// A conditional block to execute only if [condition] is satisified.
///
/// Intended for use with [If.block].
class ElseIf {
  /// A condition to match against to determine if [then] should be executed.
  final Logic condition;

  /// The [Conditional]s to execute if [condition] is satisfied.
  final List<Conditional> then;

  /// If [condition] is 1, then [then] will be executed.
  ElseIf(this.condition, this.then) {
    if (condition.width != 1) {
      throw PortWidthMismatchException(condition, 1);
    }
  }

  /// If [condition] is 1, then [then] will be executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  ElseIf.s(Logic condition, Conditional then) : this(condition, [then]);
}

/// A conditional block to execute only if `condition` is satisified.
///
/// Intended for use with [If.block].
typedef Iff = ElseIf;

/// A conditional block to execute only if [condition] is satisified.
///
/// This should come last in [If.block].
class Else extends Iff {
  /// If none of the proceding [Iff] or [ElseIf] are executed, then
  /// [then] will be executed.
  Else(List<Conditional> then) : super(Const(1), then);

  /// If none of the proceding [Iff] or [ElseIf] are executed, then
  /// [then] will be executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  Else.s(Conditional then) : this([then]);
}

/// Represents a chain of blocks of code to be conditionally executed, like
/// `if`/`else if`/`else`.
///
/// This is functionally equivalent to chaining together [If]s, but this syntax
/// is a little nicer for long chains.
@Deprecated('Use `If.block` instead.')
class IfBlock extends If {
  /// Checks the conditions for [iffs] in order and executes the first one
  /// whose condition is enabled.
  @Deprecated('Use `If.block` instead.')
  IfBlock(super.iffs) : super.block();
}

/// Represents a chain of blocks of code to be conditionally executed, like
/// `if`/`else if`/`else`.
class If extends Conditional {
  /// A set of conditional items to check against for execution, in order.
  ///
  /// The first item should be an [Iff], and if an [Else] is included it must
  /// be the last item.  Any other items should be [ElseIf].  It is okay to
  /// make the first item an [ElseIf], it will act just like an [Iff]. If an
  /// [Else] is included, it cannot be the only element (it must be preceded
  /// by an [Iff] or [ElseIf]).
  final List<Iff> iffs;

  /// If [condition] is high, then [then] executes, otherwise [orElse] is
  /// executed.
  If(Logic condition, {List<Conditional>? then, List<Conditional>? orElse})
      : this.block([
          Iff(condition, then ?? []),
          if (orElse != null) Else(orElse),
        ]);

  /// If [condition] is high, then [then] is excutes,
  /// otherwise [orElse] is executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  /// An optional [orElse] condition can be passed.
  If.s(Logic condition, Conditional then, [Conditional? orElse])
      : this(condition, then: [then], orElse: orElse == null ? [] : [orElse]);

  /// Checks the conditions for [iffs] in order and executes the first one
  /// whose condition is enabled.
  If.block(this.iffs) {
    for (final iff in iffs) {
      if (iff is Else) {
        if (iff != iffs.last) {
          throw InvalidConditionalException(
              'Else must come last in an IfBlock.');
        }

        if (iff == iffs.first) {
          throw InvalidConditionalException(
              'Else cannot be the first in an IfBlock.');
        }
      }
    }
  }

  @override
  void execute(Set<Logic> drivenSignals, [void Function(Logic)? guard]) {
    if (guard != null) {
      for (final iff in iffs) {
        guard(iff.condition);
      }
    }

    for (final iff in iffs) {
      if (driverValue(iff.condition) == LogicValue.one) {
        for (final conditional in iff.then) {
          conditional.execute(drivenSignals, guard);
        }
        break;
      } else if (driverValue(iff.condition) != LogicValue.zero) {
        // x and z propagation
        for (final receiver in receivers) {
          receiverOutput(receiver).put(driverValue(iff.condition)[0]);
          if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
            drivenSignals.add(receiver);
          }
        }
        break;
      }
      // if it's 0, then continue searching down the path
    }
  }

  @override
  late final List<Conditional> conditionals =
      UnmodifiableListView(_getConditionals());

  /// Calculates the set of conditionals directly within this.
  List<Conditional> _getConditionals() => iffs
      .map((iff) => iff.then)
      .expand((conditional) => conditional)
      .toList(growable: false);

  @override
  late final List<Logic> drivers = _getDrivers();

  /// Calculates the set of drivers recursively down.
  List<Logic> _getDrivers() {
    final drivers = <Logic>[];
    for (final iff in iffs) {
      drivers
        ..add(iff.condition)
        ..addAll(iff.then
            .map((conditional) => conditional.drivers)
            .expand((driver) => driver)
            .toList(growable: false));
    }
    return drivers;
  }

  @override
  late final List<Logic> receivers = _getReceivers();

  @override
  List<Logic> _getReceivers() {
    final receivers = <Logic>[];
    for (final iff in iffs) {
      receivers.addAll(iff.then
          .map((conditional) => conditional.receivers)
          .expand((receiver) => receiver)
          .toList(growable: false));
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final verilog = StringBuffer();
    for (final iff in iffs) {
      final header = iff == iffs.first
          ? 'if'
          : iff is Else
              ? 'else'
              : 'else if';

      final conditionName = inputsNameMap[driverInput(iff.condition).name];
      final ifContents = iff.then
          .map((conditional) => conditional.verilogContents(
              indent + 2, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      final condition = iff is! Else ? '($conditionName)' : '';
      verilog.write('''
$padding$header$condition begin
$ifContents
${padding}end ''');
    }
    verilog.write('\n');

    return verilog.toString();
  }

  @override
  Map<Logic, Logic> _processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    // add an empty else if there isn't already one, since we need it for phi
    if (iffs.last is! Else) {
      iffs.add(Else([]));
    }

    // first connect direct drivers into the if statements
    for (final iff in iffs) {
      Conditional._connectSsaDriverFromMappings(iff.condition, currentMappings,
          context: context);
    }

    // calculate mappings locally within each if statement
    final phiMappings = <Logic, Logic>{};
    for (final conditionals in iffs.map((e) => e.then)) {
      var localMappings = {...currentMappings};

      for (final conditional in conditionals) {
        localMappings =
            conditional._processSsa(localMappings, context: context);
      }

      for (final localMapping in localMappings.entries) {
        if (!phiMappings.containsKey(localMapping.key)) {
          phiMappings[localMapping.key] = Logic(
            name: '${localMapping.key.name}_phi',
            width: localMapping.key.width,
          );
        }

        conditionals.add(phiMappings[localMapping.key]! < localMapping.value);
      }
    }

    final newMappings = <Logic, Logic>{...currentMappings}..addAll(phiMappings);

    // find all the SSA signals that are driven by anything in this if block,
    // since we need to ensure every case drives them or else we may create
    // an inferred latch
    final signalsNeedingInit = iffs
        .map((e) => e.then)
        .flattened
        .map((e) => e._getReceivers())
        .flattened
        .whereType<_SsaLogic>()
        .toSet();
    for (final iff in iffs) {
      final alreadyDrivenSsaSignals = iff.then
          .map((e) => e._getReceivers())
          .flattened
          .whereType<_SsaLogic>()
          .toSet();

      for (final signalNeedingInit in signalsNeedingInit) {
        if (!alreadyDrivenSsaSignals.contains(signalNeedingInit)) {
          iff.then.add(signalNeedingInit < 0);
        }
      }
    }

    return newMappings;
  }
}

/// Constructs a positive edge triggered flip flop on [clk].
///
/// It returns [FlipFlop.q]. When optional [en] is provided, an additional
/// input will be created for flop. If optional [en] is high or not provided,
/// output will vary as per input[d]. For low [en], output remains frozen
/// irrespective of input [d]
Logic flop(Logic clk, Logic d, {Logic? en}) => FlipFlop(clk, d, en: en).q;

/// Represents a single flip-flop with no reset.
class FlipFlop extends Module with CustomSystemVerilog {
  /// Name for the enable input of this flop
  late final String _enName;

  /// Name for the clk of this flop.
  late final String _clkName;

  /// Name for the input of this flop.
  late final String _dName;

  /// Name for the output of this flop.
  late final String _qName;

  /// The clock, posedge triggered.
  late final Logic _clk = input(_clkName);

  /// Optional enable input to the flop.
  ///
  /// If enable is  high or enable is not provided then flop output will vary
  /// on the basis of clock [_clk] and input [_d]. If enable is low, then
  /// output of the flop remains frozen irrespective of the input [_d].
  late final Logic _en = input(_enName);

  /// The input to the flop.
  late final Logic _d = input(_dName);

  /// The output of the flop.
  late final Logic q = output(_qName);

  /// To track if optional enable is provided or not.
  late final bool _isEnableProvided;

  /// Constructs a flip flop which is positive edge triggered on [clk].
  ///
  /// When optional [en] is provided, an additional input will be created for
  /// flop. If optional [en] is high or not provided, output will vary as per
  /// input[d]. For low [en], output remains frozen irrespective of input [d]
  FlipFlop(Logic clk, Logic d, {Logic? en, super.name = 'flipflop'}) {
    if (clk.width != 1) {
      throw Exception('clk must be 1 bit');
    }

    _clkName = Module.unpreferredName('clk');
    _dName = Module.unpreferredName('d');
    _qName = Module.unpreferredName('q');

    addInput(_clkName, clk);
    addInput(_dName, d, width: d.width);
    addOutput(_qName, width: d.width);

    if (en != null) {
      if (en.width != 1) {
        throw PortWidthMismatchException(en, 1);
      }
      _enName = Module.unpreferredName('en');
      addInput(_enName, en);
      _isEnableProvided = true;

      _setupWithEnable();
    } else {
      _isEnableProvided = false;

      _setup();
    }
  }

  /// Performs setup for custom functional behavior.
  void _setup() {
    Sequential(_clk, [q < _d]);
  }

  /// Performs setup for custom functional behavior with enable
  void _setupWithEnable() {
    Sequential(_clk, [
      If(_en, then: [q < _d])
    ]);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (_isEnableProvided) {
      if (inputs.length != 3 || outputs.length != 1) {
        throw Exception('FlipFlop has exactly three inputs and one output.');
      }
    } else {
      if (inputs.length != 2 || outputs.length != 1) {
        throw Exception('FlipFlop has exactly two inputs and one output.');
      }
    }

    final clk = inputs[_clkName]!;
    final d = inputs[_dName]!;
    final q = outputs[_qName]!;

    if (_isEnableProvided) {
      final en = inputs[_enName]!;
      return 'always_ff @(posedge $clk) if($en) $q <= $d;  // $instanceName';
    } else {
      return 'always_ff @(posedge $clk) $q <= $d;  // $instanceName';
    }
  }
}
