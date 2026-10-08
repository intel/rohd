// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_controller.dart
// FSM controller module for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// States for the [FilterController] finite state machine.
enum FilterState {
  /// Waiting for the start signal.
  idle,

  /// Accepting initial samples into the delay line.
  loading,

  /// Normal filtering operation.
  running,

  /// Flushing the pipeline after the input stream ends.
  draining,

  /// Processing complete.
  done,
}

/// Controls the filter bank operation via a [FiniteStateMachine].
///
/// - idle: waiting for start signal
/// - loading: accepting initial samples into delay line
/// - running: normal filtering
/// - draining: flushing pipeline after input stream ends
/// - done: processing complete
class FilterController extends Module {
  /// Encoded FSM state (3 bits).
  Logic get state => output('state');

  /// High while the filter channels should be processing.
  Logic get filterEnable => output('filterEnable');

  /// High during the initial sample-loading phase.
  Logic get loadingPhase => output('loadingPhase');

  /// Asserted when the filter bank has finished processing.
  Logic get doneFlag => output('doneFlag');

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Start input.
  @protected
  Logic get startPin => input('start');

  /// Input valid.
  @protected
  Logic get inputValidPin => input('inputValid');

  /// Input done.
  @protected
  Logic get inputDonePin => input('inputDone');

  late final FiniteStateMachine<FilterState> _fsm;

  /// Returns the FSM's current state index for a given [FilterState].
  int? getStateIndex(FilterState s) => _fsm.getStateIndex(s);

  /// Creates a [FilterController] that sequences the filter bank.
  ///
  /// After [start] is asserted the FSM moves through loading → running
  /// → draining (for [drainCycles] cycles) → done.
  FilterController(
      Logic clk, Logic reset, Logic start, Logic inputValid, Logic inputDone,
      {required int drainCycles, super.name = 'FilterController'})
      : super(definitionName: 'FilterController') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    start = addInput('start', start);
    inputValid = addInput('inputValid', inputValid);
    inputDone = addInput('inputDone', inputDone);

    final filterEnable = addOutput('filterEnable');
    final loadingPhase = addOutput('loadingPhase');
    final doneFlag = addOutput('doneFlag');
    final state = addOutput('state', width: 3);

    // Drain counter
    final drainCount = Logic(width: 8, name: 'drainCount');
    final drainDone =
        drainCount.eq(Const(drainCycles, width: 8)).named('drainDone');

    _fsm = FiniteStateMachine<FilterState>(
      clk,
      reset,
      FilterState.idle,
      [
        State<FilterState>(
          FilterState.idle,
          events: {
            start: FilterState.loading,
          },
          actions: [
            filterEnable < 0,
            loadingPhase < 0,
            doneFlag < 0,
          ],
        ),
        State<FilterState>(
          FilterState.loading,
          events: {
            inputValid: FilterState.running,
          },
          actions: [
            filterEnable < 1,
            loadingPhase < 1,
            doneFlag < 0,
          ],
        ),
        State<FilterState>(
          FilterState.running,
          events: {
            inputDone: FilterState.draining,
          },
          actions: [
            filterEnable < 1,
            loadingPhase < 0,
            doneFlag < 0,
          ],
        ),
        State<FilterState>(
          FilterState.draining,
          events: {
            drainDone: FilterState.done,
          },
          actions: [
            filterEnable < 1,
            loadingPhase < 0,
            doneFlag < 0,
          ],
        ),
        State<FilterState>(
          FilterState.done,
          events: {},
          actions: [
            filterEnable < 0,
            loadingPhase < 0,
            doneFlag < 1,
          ],
        ),
      ],
    );

    state <= _fsm.currentState.zeroExtend(state.width);

    // Drain counter: Sequential block increments while draining,
    // resets to zero otherwise.
    final drainIdx = _fsm.getStateIndex(FilterState.draining)!;
    final isDraining = Logic(name: 'isDraining');
    isDraining <= _fsm.currentState.eq(Const(drainIdx, width: _fsm.stateWidth));

    Sequential(clk, reset: reset, [
      If(isDraining, then: [
        drainCount < drainCount + Const(1, width: 8),
      ], orElse: [
        drainCount < Const(0, width: 8),
      ]),
    ]);
  }
}
