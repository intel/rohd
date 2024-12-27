import 'dart:async';
import 'dart:collection';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/duplicate_detection_set.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/modules/conditionals/always.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// Deprecated: use [Sequential] instead.
@Deprecated('Use Sequential instead')
typedef FF = Sequential;

/// A tracking construct for triggers of [Sequential]s.
class _SequentialTrigger {
  /// The signal for this trigger.
  final Logic signal;

  /// Whether this triggers on a positive edge (`true`) or a negative edge
  /// (`false`).
  final bool isPosedge;

  /// The value of the trigger before the tick.
  LogicValue? preTickValue;

  /// Creates a tracking object for triggers.
  _SequentialTrigger(this.signal, {required this.isPosedge})
      : _edgeCheck = isPosedge ? LogicValue.isPosedge : LogicValue.isNegedge;

  /// The method for checking whether an edge has occurred.
  final bool Function(LogicValue previousValue, LogicValue newValue) _edgeCheck;

  /// The previous value of the signal.
  LogicValue get _previousValue =>
      // if the pre-tick value is null, then it should have the same value as
      // it currently does
      preTickValue ?? signal.value;

  /// Whether this trigger has been triggered.
  bool get isTriggered => isValid && _edgeCheck(_previousValue, signal.value);

  /// Whether this trigger is valid.
  bool get isValid => signal.value.isValid && _previousValue.isValid;

  /// The SystemVerilog keyword for this trigger.
  String get verilogTriggerKeyword => isPosedge ? 'posedge' : 'negedge';

  @override
  String toString() => '@$verilogTriggerKeyword ${signal.name}';
}

/// A tracking construct for potential race conditions between triggers and
/// non-triggers in [Sequential]s.
///
/// In general, if a trigger and non-trigger toggle "simulatneously" during the
/// same time step, then the outputs of the [Sequential] should be driven to
/// [LogicValue.x], since it is unpredictable how it will be synthesized.
class _SequentialTriggerRaceTracker {
  /// Tracks whether a trigger has occurred in this timestep.
  bool _triggerOccurred = false;

  /// Tracks whether a non-trigger has occurred in this timestep.
  bool _nonTriggerOccurred = false;

  /// Indicates whether the current timestep has violated the rules for the race
  /// condition.
  bool get isInViolation => _triggerOccurred && _nonTriggerOccurred;

  /// A collection of non-trigger inputs that have changed this tick.
  final TraverseableCollection<Logic> _nonTriggeredInputs =
      TraverseableCollection();

  /// Should be called when a trigger has occurred.
  void triggered() {
    _triggerOccurred = true;
    _registerPostTick();
  }

  /// Should be called when a non-trigger has occurred.
  void nonTriggered(Logic input) {
    _nonTriggerOccurred = true;
    _nonTriggeredInputs.add(input);
    _registerPostTick();
  }

  /// Applies [action] to all [nonTriggered] inputs.
  void applyToNonTriggeredInputs(void Function(Logic input) action) {
    _nonTriggeredInputs.forEach(action);
  }

  void Function()? _preNonTriggerClearAction;
  void registerPreNonTriggerClearAction(void Function() action) {
    _registerPostTick();
    _preNonTriggerClearAction = action;
  }

  /// Whether a post-tick has been registered alreayd for this timestep.
  bool _registeredPostTick = false;

  /// Registers a post-tick event to clear the flags.
  void _registerPostTick() {
    if (!_registeredPostTick) {
      unawaited(Simulator.postTick.first.then((value) {
        _registeredPostTick = false;
        _triggerOccurred = false;
        _nonTriggerOccurred = false;
        _preNonTriggerClearAction?.call();
        _nonTriggeredInputs.clear();
      }));

      _registeredPostTick = true;
    }
  }
}

/// Represents a block of sequential logic.
///
/// This is similar to an `always_ff` block in SystemVerilog. Edge triggered by
/// either one trigger or multiple with [Sequential.multi].
class Sequential extends Always {
  /// The input edge triggers used in this block.
  final List<_SequentialTrigger> _triggers = [];

  /// When `false`, an [SignalRedrivenException] will be thrown during
  /// simulation if the same signal is driven multiple times within this
  /// [Sequential].
  final bool allowMultipleAssignments;

  /// Indicates whether provided `reset` signals should be treated as an async
  /// reset. If no `reset` is provided, this will have no effect.
  final bool asyncReset;

  /// Constructs a [Sequential] single-triggered by the positive edge of [clk].
  ///
  /// If `reset` is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high. The default reset value is to
  /// `0`, but if `resetValues` is provided then the corresponding value
  /// associated with the driven signal will be set to that value instead upon
  /// reset. If a signal is in `resetValues` but not driven by any other
  /// [Conditional] in this block, it will be driven to the specified reset
  /// value.
  ///
  /// If [asyncReset] is true, the [reset] signal (if provided) will be treated
  /// as an async reset. If [asyncReset] is false, the reset signal will be
  /// treated as synchronous.
  Sequential(
    Logic clk,
    List<Conditional> conditionals, {
    Logic? reset,
    Map<Logic, dynamic>? resetValues,
    bool asyncReset = false,
    bool allowMultipleAssignments = true,
    String name = 'sequential',
  }) : this.multi(
          [clk],
          conditionals,
          name: name,
          reset: reset,
          asyncReset: asyncReset,
          resetValues: resetValues,
          allowMultipleAssignments: allowMultipleAssignments,
        );

  /// Constructs a [Sequential] multi-triggered by any of [posedgeTriggers] and
  /// [negedgeTriggers] (on positive and negative edges, respectively).
  ///
  /// If `reset` is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high. The default reset value is to
  /// `0`, but if `resetValues` is provided then the corresponding value
  /// associated with the driven signal will be set to that value instead upon
  /// reset. If a signal is in `resetValues` but not driven by any other
  /// [Conditional] in this block, it will be driven to the specified reset
  /// value.
  ///
  /// If [asyncReset] is true, the [reset] signal (if provided) will be treated
  /// as an async reset. If [asyncReset] is false, the reset signal will be
  /// treated as synchronous.
  ///
  /// If a trigger signal is sampled within the `conditionals`, the value will
  /// be the "new" value of that trigger, as opposed to the "old" value as with
  /// other non-trigger signals. This is meant to help model how an asynchronous
  /// trigger (e.g. async reset) could affect the behavior of the sequential
  /// elements implied. One must be careful to describe logic which is
  /// synthesizable. The [Sequential] will attempt to drive `X` in scenarios it
  /// can detect may not simulate and synthesize the same way, but it cannot
  /// guarantee it. If both a trigger and an input that is not a trigger glitch
  /// simultaneously during the phases of the [Simulator], then all outputs of
  /// this [Sequential] will be driven to [LogicValue.x].
  Sequential.multi(
    List<Logic> posedgeTriggers,
    super._conditionals, {
    Logic? reset,
    super.resetValues,
    this.asyncReset = false,
    super.name = 'sequential',
    this.allowMultipleAssignments = true,
    List<Logic> negedgeTriggers = const [],
  }) : super(reset: reset) {
    _registerInputTriggers([
      ...posedgeTriggers,
      if (reset != null && asyncReset) reset,
    ], isPosedge: true);
    _registerInputTriggers(negedgeTriggers, isPosedge: false);

    if (_triggers.isEmpty) {
      throw IllegalConfigurationException('Must provide at least one trigger.');
    }

    _setup();
  }

  /// Registers either positive or negative edge trigger inputs for
  /// [providedTriggers] based on [isPosedge].
  void _registerInputTriggers(List<Logic> providedTriggers,
      {required bool isPosedge}) {
    for (var i = 0; i < providedTriggers.length; i++) {
      final trigger = providedTriggers[i];
      if (trigger.width != 1) {
        throw Exception('Each clk or trigger must be 1 bit, but saw $trigger.');
      }

      if (assignedDriverToInputMap.containsKey(trigger)) {
        _driverInputsThatAreTriggers.add(assignedDriverToInputMap[trigger]!);
      }

      _triggers.add(_SequentialTrigger(
          addInput(
              portUniquifier.getUniqueName(
                  initialName: Sanitizer.sanitizeSV(
                      Naming.unpreferredName('trigger${i}_${trigger.name}'))),
              trigger),
          isPosedge: isPosedge));
    }
  }

  /// A map from input [Logic]s to the values that should be used for
  /// computations on the edge.
  final Map<Logic, LogicValue> _inputToPreTickInputValuesMap =
      HashMap<Logic, LogicValue>();

  /// Keeps track of whether the clock has glitched and an [_execute] is
  /// necessary.
  bool _pendingExecute = false;

  /// A set of drivers whose values in [_inputToPreTickInputValuesMap] need
  /// updating after the tick completes.
  final Set<Logic> _driverInputsPendingPostUpdate = {};

  /// Keeps track of whether values need to be updated post-tick.
  bool _pendingPostUpdate = false;

  /// All [input]s which are also triggers.
  final Set<Logic> _driverInputsThatAreTriggers = {};

  /// Updates the [_inputToPreTickInputValuesMap], if appropriate.
  ///
  /// Returns `true` only if the map was updated.  If `false`, then the input
  /// was a trigger.
  bool _updateInputToPreTickInputValue(Logic driverInput,
      {LogicValue? overrideValue}) {
    if (_driverInputsThatAreTriggers.contains(driverInput)) {
      // triggers should be sampled at the new value, not the previous value
      return false;
    }

    _inputToPreTickInputValuesMap[driverInput] =
        overrideValue ?? driverInput.value;
    return true;
  }

  /// A tracking construct for potential race conditions between triggers and
  /// non-triggers.
  final _SequentialTriggerRaceTracker _raceTracker =
      _SequentialTriggerRaceTracker();

  /// Performs setup steps for custom functional behavior of this block.
  void _setup() {
    // one time is enough, it's a final map
    for (final element in conditionals) {
      element.updateOverrideMap(_inputToPreTickInputValuesMap);
    }

    // listen to every input of this `Sequential` for changes
    for (final driverInput in assignedDriverToInputMap.values) {
      // pre-fill the _inputToPreTickInputValuesMap so that nothing ever
      // uses values directly
      _updateInputToPreTickInputValue(driverInput);

      driverInput.glitch.listen((event) async {
        if (Simulator.phase != SimulatorPhase.clkStable) {
          // if the change happens not when the clocks are stable, immediately
          // update the map
          final didUpdate = _updateInputToPreTickInputValue(driverInput);

          if (didUpdate && Simulator.phase != SimulatorPhase.outOfTick) {
            _raceTracker.nonTriggered(driverInput);
          }
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
                  _driverInputsPendingPostUpdate
                    ..forEach(_updateInputToPreTickInputValue)
                    ..clear();
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
    for (final trigger in _triggers) {
      trigger.signal.glitch.listen((event) async {
        // we want the first previousValue from the first glitch of this tick
        trigger.preTickValue ??= event.previousValue;

        if (Simulator.phase != SimulatorPhase.outOfTick) {
          _raceTracker.triggered();
        }

        if (!_pendingExecute) {
          unawaited(Simulator.clkStable.first.then((value) {
            // once the clocks are stable, execute the contents of the seq
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

  /// Drives [LogicValue.x] on all outputs of this [Sequential].
  void _driveX() {
    for (final receiverOutput in assignedReceiverToOutputMap.values) {
      receiverOutput.put(LogicValue.x);
    }
  }

  void _execute() {
    final anyTriggered = _triggers.any((t) => t.isTriggered);
    final anyTriggerInvalid = _triggers.any((t) => !t.isValid);

    if (anyTriggerInvalid) {
      _driveX();
    } else if (anyTriggered) {
      if (_raceTracker.isInViolation) {
        _raceTracker
          // update affected inputs to have an overridden value of X
          ..applyToNonTriggeredInputs((nti) =>
              _updateInputToPreTickInputValue(nti, overrideValue: LogicValue.x))

          // now, remember to change the values back to safe values after exec
          ..registerPreNonTriggerClearAction(() => _raceTracker
              .applyToNonTriggeredInputs(_updateInputToPreTickInputValue));
      }

      if (allowMultipleAssignments) {
        for (final element in conditionals) {
          // ignore: invalid_use_of_protected_member
          element.execute(null, null);
        }
      } else {
        final allDrivenSignals = DuplicateDetectionSet<Logic>();
        for (final element in conditionals) {
          // ignore: invalid_use_of_protected_member
          element.execute(allDrivenSignals, null);
        }
        if (allDrivenSignals.hasDuplicates) {
          throw SignalRedrivenException(allDrivenSignals.duplicates);
        }
      }
    }

    // clear out all the pre-tick value of clocks
    for (final trigger in _triggers) {
      trigger.preTickValue = null;
    }
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) {
    final svTriggers = _triggers
        .map((trigger) =>
            '${trigger.verilogTriggerKeyword} ${inputs[trigger.signal.name]}')
        .join(' or ');
    return 'always_ff @($svTriggers)';
  }

  @override
  String assignOperator() => '<=';
}
