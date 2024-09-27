// Copyright (C) 2021-2024 Intel Corporation
// Copyright (C) 2024 Adam Rose
// SPDX-License-Identifier: BSD-3-Clause
//
// simulator.dart
// The ROHD event-based static simulator
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>
//
// 2024 Feb 28th
// Amended by Adam Rose <adam.david.rose@gmail.com> for Rohme compatibility
//
import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

import 'package:rohd/rohd.dart';

/// An enum for the various phases of the [Simulator].
enum SimulatorPhase {
  /// Not during an active simulator tick.
  outOfTick,

  /// Before the tick has started executing.  Useful for flop sampling.
  beforeTick,

  /// Most events happen here, lots of glitches.
  mainTick,

  /// All glitchiness has completed, clocks should be stable now.
  clkStable
}

/// A functional event-based static simulator for logic behavior.
///
/// Each tick of the simulator steps through the following events and phases:
/// - [preTick]                   (event): Occurs at the very start of a tick,
///                                        before anything else occurs.
///                                        This is useful for flop sampling.
/// - [SimulatorPhase.beforeTick] (phase)
/// - [startTick]                 (event): The beginning of the "meat" of the
///                                        tick.
/// - [SimulatorPhase.mainTick]   (phase): Most events happen here, lots of
///                                        glitches.
/// - [clkStable]                 (event): All glitchiness has completed, clocks
///                                        should be stable now.
/// - [SimulatorPhase.clkStable]  (phase)
/// - [postTick]                  (event): The tick has completed, all values
///                                        should be settled.
/// - [SimulatorPhase.outOfTick]  (phase): Not during an active simulator tick.
///
/// Functional behavior modelling subscribes to [Simulator] events and/or queries the [SimulatorPhase].
abstract class Simulator {
  /// The current time in the [Simulator].
  static int get time => _currentTimestamp;
  static int _currentTimestamp = 0;

  /// Tracks whether an end to the active simulation has been requested.
  static bool _simulationEndRequested = false;

  /// Tracks for [_SimulatorException] that are thrown during the simulation.
  static List<_SimulatorException> _simExceptions = [];

  /// The maximum time the simulation can run.
  ///
  /// If set to -1 (the default), it means there is no maximum time limit.
  static int _maxSimTime = -1;

  /// A global logger object for the [Simulator].
  static final Logger logger = Logger('ROHD');

  /// Returns true iff there are more steps for the [Simulator] to tick through.
  static bool hasStepsRemaining() =>
      _pendingTimestamps.isNotEmpty || _injectedActions.isNotEmpty;

  /// Sorted storage for pending functions to execute at appropriate times.
  static final SplayTreeMap<int, ListQueue<dynamic Function()>>
      _pendingTimestamps = SplayTreeMap<int, ListQueue<dynamic Function()>>();

  /// The list of actions to be performed in this timestamp
  static ListQueue<dynamic Function()> _pendingList = ListQueue();

  /// Functions to be executed as soon as possible by the [Simulator].
  ///
  /// Actions may return [Future]s, which will be `await`ed.
  static final Queue<dynamic Function()> _injectedActions =
      Queue<dynamic Function()>();

  /// Functions to be executed at the end of the simulation.
  ///
  /// Actions may return [Future]s, which will be `await`ed.
  static final Queue<dynamic Function()> _endOfSimulationActions =
      Queue<dynamic Function()>();

  /// Emits an event before any other actions take place on the tick.
  static Stream<void> get preTick => _preTickController.stream;
  static StreamController<void> _preTickController =
      StreamController.broadcast(sync: true);

  /// Emits an event at the start of actions within a tick.
  static Stream<void> get startTick => _startTickController.stream;
  static StreamController<void> _startTickController =
      StreamController.broadcast(sync: true);

  /// Emits an event when most events are complete, and clocks are stable.
  static Stream<void> get clkStable => _clkStableController.stream;
  static StreamController<void> _clkStableController =
      StreamController.broadcast(sync: true);

  /// Emits an event after all events are completed.
  static Stream<void> get postTick => _postTickController.stream;
  static StreamController<void> _postTickController =
      StreamController.broadcast(sync: true);

  /// Completes when [reset] is called after the [Simulator] has completed any
  /// actions it needs to perform to prepare for the next simulation.
  static Future<void> get resetRequested => _resetCompleter.future;
  static Completer<void> _resetCompleter = Completer<void>();

  /// Completes when the simulation has completed.
  static Future<void> get simulationEnded => _simulationEndedCompleter.future;
  static Completer<void> _simulationEndedCompleter = Completer<void>();

  /// Returns true iff the simulation has completed.
  static bool get simulationHasEnded => _simulationEndedCompleter.isCompleted;

  /// Gets the current [SimulatorPhase] of the [Simulator].
  static SimulatorPhase get phase => _phase;
  static SimulatorPhase _phase = SimulatorPhase.outOfTick;

  /// Resets the entire [Simulator] back to its initial state.
  ///
  /// Note: values deposited on [Module]s from the previous simulation remain.
  static Future<void> reset() async {
    if (_simulationEndRequested) {
      await simulationEnded;
    }

    _currentTimestamp = 0;
    _simulationEndRequested = false;

    _simExceptions = [];

    _maxSimTime = -1;
    if (!_preTickController.isClosed) {
      await _preTickController.close();
    }
    if (!_startTickController.isClosed) {
      await _startTickController.close();
    }
    if (!_clkStableController.isClosed) {
      await _clkStableController.close();
    }
    if (!_postTickController.isClosed) {
      await _postTickController.close();
    }
    _preTickController = StreamController.broadcast(sync: true);
    _startTickController = StreamController.broadcast(sync: true);
    _clkStableController = StreamController.broadcast(sync: true);
    _postTickController = StreamController.broadcast(sync: true);
    if (!_simulationEndedCompleter.isCompleted) {
      _simulationEndedCompleter.complete();
    }
    _simulationEndedCompleter = Completer();
    _pendingTimestamps.clear();
    _phase = SimulatorPhase.outOfTick;
    _injectedActions.clear();

    // make sure we've already passed the new completer so that listeners can
    // get the latest
    final oldResetCompleter = _resetCompleter;
    _resetCompleter = Completer();
    oldResetCompleter.complete();
    await oldResetCompleter.future;
  }

  /// Sets a time, after which, the [Simulator] will halt processing of new
  /// actions.
  ///
  /// You should set this for your simulations so that you don't get infinite
  /// simulation.
  // ignore: use_setters_to_change_properties
  static void setMaxSimTime(int newMaxSimTime) {
    _maxSimTime = newMaxSimTime;
  }

  /// Registers an abritrary [action] to be executed at [timestamp] time.
  ///
  /// The [action], if it returns a [Future], will be `await`ed.
  static void registerAction(int timestamp, dynamic Function() action) {
    if (timestamp < _currentTimestamp) {
      throw SimulatorException('Cannot add timestamp "$timestamp" in the past.'
          ' Current time is ${Simulator.time}.'
          ' Did you mean to include a call to Simulator.reset()?'
          ' If this is hit in a series of unit tests, see the user guide'
          ' for tips:'
          ' https://intel.github.io/rohd-website/docs/unit-test/');
    }
    if (!_pendingTimestamps.containsKey(timestamp)) {
      _pendingTimestamps[timestamp] = ListQueue();
    }
    _pendingTimestamps[timestamp]!.add(action);
  }

  /// Cancels an [action] previously scheduled for [timestamp].
  ///
  /// Returns true iff a [action] was previously registered at [timestamp].
  static bool cancelAction(int timestamp, dynamic Function() action) {
    if (!_pendingTimestamps.containsKey(timestamp)) {
      return false;
    }

    if (!_pendingTimestamps[timestamp]!.remove(action)) {
      return false;
    }

    if (_pendingTimestamps[timestamp]!.isEmpty) {
      _pendingTimestamps.remove(timestamp);
    }

    return true;
  }

  /// Registers an arbitrary [action] to be executed at the end of the
  /// simulation.
  ///
  /// The simulation will not be marked as ended until these actions complete.
  ///
  /// If [action] returns a [Future], it will be `await`ed.
  static void registerEndOfSimulationAction(dynamic Function() action) {
    _endOfSimulationActions.add(action);
  }

  /// Adds an arbitrary [action] to be executed as soon as possible, during the
  /// current simulation tick if possible.
  ///
  /// If the injection occurs outside of a tick ([SimulatorPhase.outOfTick]),
  /// it will execute in a new tick in the same timestamp.
  ///
  /// If [action] returns a [Future], it will be `await`ed.
  static void injectAction(dynamic Function() action) {
    // adds an action to be executed in the current timestamp
    _injectedActions.addLast(action);
  }

  /// A single simulation tick.
  ///
  /// Takes the simulator through all actions within the next pending
  /// timestamp, and passes through all events and phases on the way.
  ///
  /// If there are no timestamps pending to execute, nothing will execute.
  static Future<void> tick() async {
    if (_injectedActions.isNotEmpty) {
      // case 1 : ( the usual Rohd case )
      // The previous delta cycle did NOT do
      // 'registerAction( _currentTimeStamp );'.
      // In that case, _pendingTimestamps[_currentTimestamp] is null so we will
      // add a new empty list, which will trigger a new delta cycle.
      //
      // case 2 :
      // The previous delta cycle DID do 'registerAction( _currentTimestamp );'.
      // In that case, there is *already* another tick scheduled for
      // _currentTimestamp, and the injected actions will get called in
      //  the normal way.
      //
      // Either way, the end result is that a whole new tick gets scheduled for
      // _currentTimestamp and any outstanding injected actions get executed.

      // ignore: unnecessary_lambdas
      _pendingTimestamps.putIfAbsent(_currentTimestamp, () => ListQueue());
    }

    // the main event loop
    if (_updateTimeStamp()) {
      _preTick();
      await _mainTick();
      _clkStable();
      await _outOfTick();
    }
  }

  /// Updates [_currentTimestamp] with the next time stamp.
  ///
  /// Returns true iff there is a next time stamp.
  ///
  /// Also updates [_pendingList] with the list of actions scheduled for this
  /// timestamp.
  ///
  /// If any of the actions in [_pendingList] schedule an action for
  /// [_currentTimestamp], then this action is registered in the next delta
  /// cycle. The next delta cycle is modelled as a new list of actions with the
  /// same time as [_currentTimestamp].
  static bool _updateTimeStamp() {
    final nextTimeStamp = _pendingTimestamps.firstKey();

    if (nextTimeStamp == null) {
      return false;
    }

    _currentTimestamp = nextTimeStamp;

    // remove current list of actions but keep it for use in the mainTick phase
    _pendingList = _pendingTimestamps.remove(_currentTimestamp)!;
    return true;
  }

  /// Executes the preTick phase.
  static void _preTick() {
    _phase = SimulatorPhase.beforeTick;
    _preTickController.add(null);
  }

  /// Executes the mainTick phase.
  ///
  /// After [_startTickController] is notified, this method awaits all the
  /// actions registered with this tick, removing the action from [_pendingList]
  /// as it goes.
  static Future<void> _mainTick() async {
    _phase = SimulatorPhase.mainTick;

    // useful for things that need to trigger every tick without other input
    _startTickController.add(null);

    // execute the actions for this timestamp
    while (_pendingList.isNotEmpty) {
      await _pendingList.removeFirst()();
    }
  }

  /// Executes the clkStable phase
  static void _clkStable() {
    _phase = SimulatorPhase.clkStable;

    // useful for flop clk input stability
    _clkStableController.add(null);
  }

  /// Executes the outOfTick phase
  ////
  /// Just before we end the current tick, we execute the injected actions,
  /// removing them from [_injectedActions] as we go.
  static Future<void> _outOfTick() async {
    while (_injectedActions.isNotEmpty) {
      final injectedFunction = _injectedActions.removeFirst();
      await injectedFunction();
    }

    _phase = SimulatorPhase.outOfTick;

    // useful for determination of signal settling
    _postTickController.add(null);
  }

  /// Halts the simulation.  Allows the current [tick] to finish, if there
  /// is one.
  ///
  /// The [Future] returned is equivalent to [simulationEnded] and completes
  /// once the simulation has actually ended.
  static Future<void> endSimulation() async {
    _simulationEndRequested = true;

    // wait for the simulation to actually end
    await simulationEnded;
  }

  /// Collects an [exception] and associated [stackTrace] triggered
  /// asynchronously during simulation to be thrown synchronously by [run].
  ///
  /// Calling this function will end the simulation after this [tick] completes.
  static void throwException(Exception exception, StackTrace stackTrace) {
    _simExceptions.add(_SimulatorException(exception, stackTrace));
  }

  /// Starts the simulation, executing all pending actions in time-order until
  /// it finishes or is stopped.
  static Future<void> run() async {
    if (simulationHasEnded) {
      throw Exception('Simulation has already been run and ended.'
          '  To run a new simulation, use Simulator.reset().');
    }

    while (hasStepsRemaining() &&
        _simExceptions.isEmpty &&
        !_simulationEndRequested &&
        (_maxSimTime < 0 || _currentTimestamp < _maxSimTime)) {
      try {
        await tick();
      } catch (__, _) {
        // trigger the end of simulation if an error occurred
        _simulationEndedCompleter.complete();

        rethrow;
      }
    }

    for (final err in _simExceptions) {
      logger.severe(err.exception.toString(), err.exception, err.stackTrace);

      // trigger the end of simulation if an error occurred
      _simulationEndedCompleter.complete();

      throw err.exception;
    }

    if (_currentTimestamp >= _maxSimTime && _maxSimTime > 0) {
      logger.warning('Simulation ended due to maximum simulation time.');
    }

    while (_endOfSimulationActions.isNotEmpty) {
      final endOfSimAction = _endOfSimulationActions.removeFirst();

      try {
        await endOfSimAction();
      } catch (_) {
        // trigger the end of simulation if an error occurred
        _simulationEndedCompleter.complete();

        rethrow;
      }
    }

    _simulationEndedCompleter.complete();
    await simulationEnded;
  }
}

/// A simulator exception that produces object of exception and stack trace.
class _SimulatorException {
  /// Tracks for [Exception] thrown during [Simulator] `run()`.
  final Exception exception;

  /// Tracks for [StackTrace] thrown during [Simulator] `run()`.
  final StackTrace stackTrace;

  /// Constructs a simulator exception, using [exception] and [stackTrace].
  _SimulatorException(this.exception, this.stackTrace);
}
