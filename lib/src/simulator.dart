/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// simulator.dart
/// The ROHD event-based static simulator
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

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
class Simulator {
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
  static final SplayTreeMap<int, List<dynamic Function()>> _pendingTimestamps =
      SplayTreeMap<int, List<dynamic Function()>>();

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

  /// Emits an event at the start of actions within a tick.
  static Stream<void> get startTick => _startTickController.stream;

  /// Emits an event when most events are complete, and clocks are stable.
  static Stream<void> get clkStable => _clkStableController.stream;

  /// Emits an event after all events are completed.
  static Stream<void> get postTick => _postTickController.stream;

  static StreamController<void> _preTickController =
      StreamController.broadcast(sync: true);
  static StreamController<void> _startTickController =
      StreamController.broadcast(sync: true);
  static StreamController<void> _clkStableController =
      StreamController.broadcast(sync: true);
  static StreamController<void> _postTickController =
      StreamController.broadcast(sync: true);

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
    if (timestamp <= _currentTimestamp) {
      throw Exception('Cannot add timestamp "$timestamp" in the past.'
          '  Current time is ${Simulator.time}');
    }
    if (!_pendingTimestamps.containsKey(timestamp)) {
      _pendingTimestamps[timestamp] = [];
    }
    _pendingTimestamps[timestamp]!.add(action);
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
      // injected actions will automatically be executed during tickExecute
      await tickExecute(() {});

      // don't continue through the tick for injected actions, come back around
      return;
    }

    final nextTimeStamp = _pendingTimestamps.firstKey();
    if (nextTimeStamp == null) {
      return;
    }

    _currentTimestamp = nextTimeStamp;

    await tickExecute(() async {
      for (final func in _pendingTimestamps[nextTimeStamp]!) {
        await func();
      }
    });
    _pendingTimestamps.remove(_currentTimestamp);
  }

  /// Executes all pending injected actions.
  static Future<void> _executeInjectedActions() async {
    while (_injectedActions.isNotEmpty) {
      final injectedFunction = _injectedActions.removeFirst();
      await injectedFunction();
    }
  }

  /// Performs the actual execution of a collection of actions for a [tick()].
  static Future<void> tickExecute(dynamic Function() toExecute) async {
    _phase = SimulatorPhase.beforeTick;

    // useful for flop sampling
    _preTickController.add(null);

    _phase = SimulatorPhase.mainTick;

    // useful for things that need to trigger every tick without other input
    _startTickController.add(null);
    await toExecute();

    _phase = SimulatorPhase.clkStable;

    // useful for flop clk input stability
    _clkStableController.add(null);

    await _executeInjectedActions();

    _phase = SimulatorPhase.outOfTick;

    // useful for determination of signal settling
    _postTickController.add(null);
  }

  /// Halts the simulation.  Allows the current [tick] to finish, if there
  /// is one.
  static void endSimulation() {
    _simulationEndRequested = true;
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
      await tick();
    }

    for (final err in _simExceptions) {
      logger.severe(err.exception.toString(), err.exception, err.stackTrace);
      throw err.exception;
    }

    if (_currentTimestamp >= _maxSimTime && _maxSimTime > 0) {
      logger.warning('Simulation ended due to maximum simulation time.');
    }

    while (_endOfSimulationActions.isNotEmpty) {
      final endOfSimAction = _endOfSimulationActions.removeFirst();
      await endOfSimAction();
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
