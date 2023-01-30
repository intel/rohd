/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// state_machine.dart
/// fsm generators
///
/// 2022 April 22
/// Author: Shubham Kumar <shubham.kumar@intel.com>
///

import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:rohd/rohd.dart';

/// Simple class for FSM [StateMachine].
///
/// Abstraction for representing Finite state machines (FSM).
/// Contains the logic for performing the state transitions.
class StateMachine<StateIdentifier> {
  /// List containig objects of class [State].
  List<State<StateIdentifier>> get states => UnmodifiableListView(_states);
  final List<State<StateIdentifier>> _states;

  /// A map to store the state identifier as the key and the object as the value
  final Map<StateIdentifier, State<StateIdentifier>> _stateLookup = {};

  /// A map to store the state object as the key and the index of the state in
  /// _states as the value.
  final Map<State<StateIdentifier>, int> _stateValueLookup = {};

  /// The clock signal to the FSM.
  final Logic clk;

  /// The reset signal to the FSM.
  final Logic reset;

  /// The reset state of the FSM to default to when the reset signal is high.
  final StateIdentifier resetState;

  /// The current state of the FSM.
  final Logic currentState;

  /// The next state of the FSM.
  final Logic nextState;

  static int _logBase(num x, num base) => (log(x) / log(base)).ceil();

  /// Width of the state.
  final int _stateWidth;

  /// Constructs a simple FSM, using the [clk] and [reset] signals. Also accepts
  /// the reset state to transition to [resetState] along with the [List] of
  /// [_states] of the FSM.
  ///
  /// If a [reset] signal is provided the FSM transitions to the [resetState]
  /// on the next clock cycle.
  StateMachine(this.clk, this.reset, this.resetState, this._states)
      : _stateWidth = _logBase(_states.length, 2),
        currentState =
            Logic(name: 'currentState', width: _logBase(_states.length, 2)),
        nextState =
            Logic(name: 'nextState', width: _logBase(_states.length, 2)) {
    var stateCounter = 0;

    for (final state in _states) {
      _stateLookup[state.identifier] = state;
      _stateValueLookup[state] = stateCounter++;
    }

    Combinational([
      Case(
          currentState,
          _states
              .map((state) => CaseItem(
                      Const(_stateValueLookup[state], width: _stateWidth), [
                    ...state.actions,
                    Case(
                        Const(1),
                        state.events.entries
                            .map((entry) => CaseItem(entry.key, [
                                  nextState <
                                      _stateValueLookup[
                                          _stateLookup[entry.value]]
                                ]))
                            .toList(),
                        conditionalType: ConditionalType.unique,
                        defaultItem: [nextState < currentState])
                  ]))
              .toList(),
          conditionalType: ConditionalType.unique,
          defaultItem: [nextState < currentState])
    ]);

    Sequential(clk, [
      If(
        reset,
        then: [currentState < _stateValueLookup[_stateLookup[resetState]]],
        orElse: [currentState < nextState],
      )
    ]);
  }

  /// Generate a FSM state diagram [MermaidStateDiagram].
  String generateDiagram({required String outputPath}) {
    final figure = MermaidStateDiagram(outputPath: outputPath)
      ..addStartState(resetState.toString());

    for (final state in _states) {
      for (final entry in state.events.entries) {
        figure.addTransitions(state.identifier.toString(),
            entry.value.toString(), entry.key.name);
      }
    }
    figure.writeToFile();
    return figure.diagram;
  }
}

/// Simple class to initialize each state of the FSM.
class State<StateIdentifier> {
  /// Identifier or name of the state.
  final StateIdentifier identifier;

  /// A map of the possible conditions that might be true and the next state
  /// that the FSM needs to transition to in each of those cases.
  final Map<Logic, StateIdentifier> events;

  /// Actions to perform while the FSM is in this state.
  final List<Conditional> actions;

  /// Represents a state named [identifier] with a definition of [events]
  /// and [actions] associated with that state.
  State(this.identifier, {required this.events, required this.actions});
}

/// A state diagram generator for FSM.
///
/// Outputs to vcd format at [outputPath].
class MermaidStateDiagram {
  /// The diagram to be return as String
  late String diagram;

  /// The output filepath of the generated state diagram.
  final String outputPath;

  /// The file to write dumped output waveform to.
  final File _outputFile;

  /// Generate a [MermaidStateDiagram] that initialized the diagram of
  /// mermaid as `stateDiagram`.
  ///
  /// Passed output path to save in custom directory.
  MermaidStateDiagram({this.outputPath = 'stateDiagram.md'})
      : _outputFile = File(outputPath) {
    diagram = 'stateDiagram\n';
  }

  /// Register a new state to the mermaid diagram object.
  void addState(String state) => diagram = '$diagram\n$state\n';

  /// Register a new transition [event] that point the
  /// current state [currState] to next state [nextState].
  void addTransitions(String currState, String nextState, String event) =>
      diagram = '$diagram$currState --> $nextState: $event\n';

  /// Register a start state [startState].
  void addStartState(String startState) =>
      diagram = '$diagram\n[*] --> $startState\n';

  /// Register a end state [endState].
  void addEndState(String endState) =>
      diagram = '$diagram\n$endState --> [*]\n';

  /// Write the object content to [_outputFile] by enclose it with
  /// mermaid identifier.
  void writeToFile() {
    diagram = '''
```mermaid
$diagram
```
''';
    _outputFile.writeAsString(diagram);
  }
}
