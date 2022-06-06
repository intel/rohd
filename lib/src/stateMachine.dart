/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// stateMachine.dart
/// fsm generators
///
/// 2022 April 22
/// Author: Shubham Kumar <shubham.kumar@intel.com>
///

import 'package:rohd/rohd.dart';
import 'dart:math';

// Simple class for fsm [StateMachine].
// Contains the logic for performing the state transitions.
class StateMachine<StateIdentifier> {
  /// List containig objects of class [State].
  List<State<StateIdentifier>> states;

  /// A map to store the state identifier as the key and the object as the value
  final Map<StateIdentifier, State> _stateLookup = {};
  final Map<State, int> _stateValueLookup = {};

  /// The clk and reset signals to the FSM.
  final Logic clk, reset;
  // The reset state of the FSM to default to when the reset signal is high.
  final StateIdentifier resetState;

  /// The current state of the FSM.
  final Logic currentState;

  /// The next state of the FSM.
  final Logic nextState;

  static int logBase(num x, num base) => (log(x) / log(base)).ceil();

  final int stateWidth;

  /// Constructs a simple FSM, using the [clk] and [reset] signals. Also accepts the reset state to transition to [resetState] along with the [List] of states of the FSM.
  ///
  /// If a [reset] signal is provided the FSM transitions to the [resetState] on the next clock cycle.
  StateMachine(this.clk, this.reset, this.resetState, this.states)
      : stateWidth = logBase(states.length, 2),
        currentState =
            Logic(name: 'currentState', width: logBase(states.length, 2)),
        nextState = Logic(name: 'nextState', width: logBase(states.length, 2)) {
    var stateCounter = 0;

    for (var state in states) {
      _stateLookup[state.identifier] = state;
      _stateValueLookup[state] = stateCounter++;
    }

    Combinational([
      Case(
          currentState,
          states
              .map((state) =>
                  CaseItem(Const(_stateValueLookup[state], width: stateWidth), [
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
}

/// Simple class to initialize each state of the FSM.
class State<StateIdentifier> {
  /// Identifier or name of the state.
  final StateIdentifier identifier;

  /// A map of the possible conditions that might be true and the next state that the FSM needs to transition to in each of those cases.
  final Map<Logic, StateIdentifier> events;

  /// Actions to  perform while the FSM is in this state.
  final List<Conditional> actions;

  State(this.identifier, {required this.events, required this.actions});
}
