// Copyright (C) 2022-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// finite_state_machine.dart
// Finite state machine generators
//
// 2022 April 22
// Author: Shubham Kumar <shubham.kumar@intel.com>

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';

/// Deprecated: use [FiniteStateMachine] instead.
@Deprecated('Use FiniteStateMachine instead')
typedef StateMachine<T> = FiniteStateMachine<T>;

/// Simple class for FSM [FiniteStateMachine].
///
/// Abstraction for representing Finite state machines (FSM).
/// Contains the logic for performing the state transitions.
class FiniteStateMachine<StateIdentifier> {
  /// List of all the [State]s in this machine.
  List<State<StateIdentifier>> get states => UnmodifiableListView(_states);
  final List<State<StateIdentifier>> _states;

  /// A map to store the state identifier as the key
  /// and the object as the value.
  final Map<StateIdentifier, State<StateIdentifier>> _stateLookup = {};

  /// A map to store the state object as the key and the index of the state in
  /// _states as the value.
  final Map<State<StateIdentifier>, int> _stateValueLookup = {};

  /// Provides the corresponding index held in state signals such as
  /// [nextState] and [currentState] based on the provided [id].
  ///
  /// Returns null if the [id] does not have a defined state in the machine.
  int? getStateIndex(StateIdentifier id) {
    if (!_stateLookup.containsKey(id)) {
      return null;
    }

    return _stateValueLookup[_stateLookup[id]];
  }

  /// A [Map] from the [StateIdentifier]s to the internal index used to
  /// represent that state in the state machine.
  // TODO: should this be overrideable?
  late final Map<StateIdentifier, int> stateIndexLookup = UnmodifiableMapView(
      _stateValueLookup.map((key, value) => MapEntry(key.identifier, value)));

  /// The clock signal to the FSM (when only single-triggered). Otherwise, the
  /// first clock.
  ///
  /// Deprecated: do not reference the clock from [FiniteStateMachine].
  @Deprecated('Do not reference the clock from the `FiniteStateMachine`.')
  Logic get clk => _clks.first;

  /// The clock signals to the FSM.
  final List<Logic> _clks;

  /// The reset signal to the FSM.
  final Logic reset;

  /// The reset state of the FSM to default to when the reset signal is high.
  final StateIdentifier resetState;

  /// The current state of the FSM.
  ///
  /// Use [getStateIndex] to map from a [StateIdentifier] to the value on this
  /// bus.
  final Logic currentState;

  /// A [List] of [Conditional] actions to perform at the beginning of the
  /// evaluation of actions for the [FiniteStateMachine].  This is useful for
  /// things like setting up default values for signals across all states.
  final List<Conditional> setupActions;

  /// The next state of the FSM.
  ///
  /// Use [getStateIndex] to map from a [StateIdentifier] to the value on this
  /// bus.
  final Logic nextState;

  /// Returns a ceiling on the log of [x] base [base].
  static int _logBase(num x, num base) => (log(x) / log(base)).ceil();

  /// Width of the state.
  final int stateWidth;

  /// If `true`, the [reset] signal is asynchronous.
  final bool asyncReset;

  /// Creates an finite state machine for the specified list of [_states], with
  /// an initial state of [resetState] (when synchronous [reset] is high) and
  /// transitions on positive [clk] edges.
  FiniteStateMachine(
    Logic clk,
    Logic reset,
    StateIdentifier resetState,
    List<State<StateIdentifier>> states, {
    bool asyncReset = false,
    List<Conditional> setupActions = const [],
  }) : this.multi([clk], reset, resetState, states,
            asyncReset: asyncReset, setupActions: setupActions);

  /// Creates an finite state machine for the specified list of [_states], with
  /// an initial state of [resetState] (when [reset] is high) and transitions on
  /// positive edges of any of [_clks].
  ///
  /// If [asyncReset] is `true`, the [reset] signal is asynchronous.
  FiniteStateMachine.multi(
    this._clks,
    this.reset,
    this.resetState,
    this._states, {
    this.asyncReset = false,
    this.setupActions = const [],
  })  : stateWidth = _logBase(_states.length, 2),
        currentState =
            Logic(name: 'currentState', width: _logBase(_states.length, 2)),
        nextState =
            Logic(name: 'nextState', width: _logBase(_states.length, 2)) {
    _validate();

    var stateCounter = 0;
    for (final state in _states) {
      _stateLookup[state.identifier] = state;
      _stateValueLookup[state] = stateCounter++;
    }

    Combinational([
      ...setupActions,
      Case(
          currentState,
          _states
              .map((state) => CaseItem(
                      label: state.identifier.toString(),
                      Const(_stateValueLookup[state], width: stateWidth)
                          .named(state.identifier.toString()),
                      [
                        ...state.actions,
                        Case(
                            Const(1),
                            state.events.entries
                                .map((entry) => CaseItem(entry.key, [
                                      nextState <
                                          _stateValueLookup[
                                              _stateLookup[entry.value]]
                                    ]))
                                .toList(growable: false),
                            conditionalType: state.conditionalType,
                            defaultItem: [
                              nextState < getStateIndex(state.defaultNextState),
                            ])
                      ]))
              .toList(growable: false),
          conditionalType: ConditionalType.unique,
          defaultItem: [
            nextState < currentState,

            // zero out all other receivers from state actions...
            // even though out-of-state is unreachable,
            // we don't want any inferred latches
            ..._states
                .map((state) => state.actions)
                .flattened
                .map((conditional) => conditional.receivers)
                .flattened
                .toSet()
                .map((receiver) => receiver < 0)
          ])
    ]);

    Sequential.multi(_clks, reset: reset, asyncReset: asyncReset, resetValues: {
      currentState: _stateValueLookup[_stateLookup[resetState]]
    }, [
      currentState < nextState,
    ]);
  }

  /// Validates that the configuration of the [FiniteStateMachine] is legal.
  void _validate() {
    final identifiers = _states.map((e) => e.identifier);

    if (identifiers.toSet().length != _states.length) {
      throw IllegalConfigurationException('State identifiers must be unique.');
    }

    if (!identifiers.contains(resetState)) {
      throw IllegalConfigurationException(
          'Reset state $resetState must have a definition.');
    }
  }

  /// Generate a FSM state diagram [_MermaidStateDiagram].
  /// Check on https://mermaid.js.org/intro/ to view the diagram generated.
  /// If you are using vscode, you can download the mermaid extension.
  ///
  /// Output to mermaid diagram at [outputPath].
  void generateDiagram({String outputPath = 'diagram_fsm.md'}) {
    final figure = _MermaidStateDiagram(outputPath: outputPath)
      ..addStartState(resetState.toString());

    for (final state in _states) {
      for (final entry in state.events.entries) {
        figure.addTransitions(
          state.identifier.toString(),
          entry.value.toString(),
          entry.key.name,
        );
      }

      if (state.defaultNextState != state.identifier) {
        figure.addTransitions(
          state.identifier.toString(),
          state.defaultNextState.toString(),
          '(default)',
        );
      }
    }
    figure.writeToFile();
  }
}

/// Simple class to initialize each state of the FSM.
class State<StateIdentifier> {
  /// Identifier or name of the state.
  final StateIdentifier identifier;

  /// A map of the possible conditions that might be true and the next state
  /// that the FSM needs to transition to in each of those cases.
  ///
  /// If no key in [events] matches, then the state of the [FiniteStateMachine]
  /// will stay the same.
  ///
  /// If using [ConditionalType.priority], this should be an ordered [Map].
  final Map<Logic, StateIdentifier> events;

  /// Actions to perform while the FSM is in this state.
  final List<Conditional> actions;

  /// The next state to transition to if non of the [events] hit.
  final StateIdentifier defaultNextState;

  /// Used to control how different [events] should be prioritized and matched.
  ///
  /// For example, if [ConditionalType.priority] is selected, then the first
  /// matching event in [events] will be executed.  If [ConditionalType.unique]
  /// is selected, then there will be a guarantee that no two [events] match
  /// at the same time.
  final ConditionalType conditionalType;

  /// Represents a state named [identifier] with a definition of [events]
  /// and [actions] associated with that state.
  ///
  /// If provided, the [defaultNextState] is the default next state if none
  /// of the [events] match.
  State(
    this.identifier, {
    required this.events,
    required this.actions,
    StateIdentifier? defaultNextState,
    this.conditionalType = ConditionalType.unique,
  }) : defaultNextState = defaultNextState ?? identifier;
}

/// A state diagram generator for FSM.
///
/// Outputs to markdown format at [outputPath].
class _MermaidStateDiagram {
  /// The diagram to be return as String.
  late StringBuffer _diagram;

  /// The output filepath of the generated state diagram.
  final String outputPath;

  /// The file to write dumped output waveform to.
  final File _outputFile;

  // An empty spaces indentation for state.
  final _indentation = ' ' * 4;

  /// Generate a [_MermaidStateDiagram] that initialized the diagram of
  /// mermaid as `stateDiagram`.
  ///
  /// Passed output path to save in custom directory.
  _MermaidStateDiagram({this.outputPath = 'diagram_fsm.md'})
      : _outputFile = File(outputPath) {
    _diagram = StringBuffer('stateDiagram-v2');
  }

  /// Register a new transition [event] that point the
  /// current state [currentState] to next state [nextState].
  void addTransitions(String currentState, String nextState, String event) =>
      _diagram.write('\n$_indentation$currentState --> $nextState: $event');

  /// Register a start state [startState].
  void addStartState(String startState) =>
      _diagram.write('\n$_indentation[*] --> $startState');

  /// Write the object content to [_outputFile] by enclose it with
  /// mermaid identifier.
  void writeToFile() {
    final outputDiagram = StringBuffer('''
```mermaid
$_diagram
```
''');
    _outputFile.writeAsStringSync(outputDiagram.toString());
  }
}
