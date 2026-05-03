// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// oven_fsm_modules.dart
// Web-safe module class definitions for the Oven FSM example.
//
// Extracted from example/oven_fsm.dart and example/example.dart so these
// classes can be imported in web-targeted code (no dart:io dependency).
//
// 2026 April
// Original authors: Yao Jing Quek, Max Korbel

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

// ──────────────────────────────────────────────────────────────────
// Counter (from example/example.dart)
// ──────────────────────────────────────────────────────────────────

/// A simple 8-bit counter with enable and synchronous reset.
class Counter extends Module {
  /// The current counter value.
  Logic get val => output('val');

  /// The enable input.
  @protected
  Logic get en => input('en');

  /// The reset input.
  @protected
  Logic get resetPin => input('reset');

  /// The clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Bit width of the counter (default 8).
  final int width;

  /// Creates a [Counter] of [width] bits driven by [clk].
  ///
  /// Increments on each rising edge when [en] is high.
  /// [reset] synchronously clears the count to zero.
  Counter(
    Logic en,
    Logic reset,
    Logic clk, {
    this.width = 8,
    super.name = 'counter',
  }) : super(definitionName: 'Counter_W$width') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    addOutput('val', width: width);

    val <= flop(clk, reset: reset, en: en, val + 1);
  }
}

// ──────────────────────────────────────────────────────────────────
// Oven FSM enums
// ──────────────────────────────────────────────────────────────────

/// Oven states: standby → cooking → paused → completed.
enum OvenState {
  /// Waiting for the start button.
  standby,

  /// Actively cooking (timer running).
  cooking,

  /// Cooking paused (timer held).
  paused,

  /// Cooking finished (timer expired).
  completed,
}

/// One-hot encoded button inputs.
enum Button {
  /// Start or restart cooking.
  start(value: 0),

  /// Pause cooking.
  pause(value: 1),

  /// Resume from pause.
  resume(value: 2);

  /// Creates a button with the given encoded [value].
  const Button({required this.value});

  /// The encoded value for this button.
  final int value;
}

/// One-hot encoded LED output colors.
enum LEDLight {
  /// Yellow — cooking in progress.
  yellow(value: 0),

  /// Blue — standby.
  blue(value: 1),

  /// Red — paused.
  red(value: 2),

  /// Green — cooking complete.
  green(value: 3);

  /// Creates an LED color with the given encoded [value].
  const LEDLight({required this.value});

  /// The encoded value for this LED color.
  final int value;
}

// ──────────────────────────────────────────────────────────────────
// OvenModule
// ──────────────────────────────────────────────────────────────────

/// A microwave oven FSM with 4 states and an internal timer counter.
///
/// Inputs:
///   - `button` (2-bit): start / pause / resume
///   - `reset`: active-high synchronous reset
///   - `clk`: clock
///
/// Outputs:
///   - `led` (2-bit): blue (standby), yellow (cooking),
///     red (paused), green (completed)
class OvenModule extends Module {
  late final FiniteStateMachine<OvenState> _oven;

  /// The LED output encoding the current state.
  Logic get led => output('led');

  /// The button input.
  @protected
  Logic get button => input('button');

  /// The reset input.
  @protected
  Logic get resetPin => input('reset');

  /// The clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Creates an [OvenModule] controlled by [button] with [clk] and [reset].
  OvenModule(Logic button, Logic reset, Logic clk)
      : super(name: 'oven', definitionName: 'OvenModule') {
    button = addInput('button', button, width: button.width);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    final led = addOutput('led', width: button.width);

    final counterReset = Logic(name: 'counter_reset');
    final en = Logic(name: 'counter_en');

    final counter = Counter(en, counterReset, clk, name: 'counter_module');

    final states = [
      State<OvenState>(OvenState.standby, events: {
        Logic(name: 'button_start')
              ..gets(button.eq(Const(Button.start.value, width: button.width))):
            OvenState.cooking,
      }, actions: [
        led < LEDLight.blue.value,
        counterReset < 1,
        en < 0,
      ]),
      State<OvenState>(OvenState.cooking, events: {
        Logic(name: 'button_pause')
              ..gets(button.eq(Const(Button.pause.value, width: button.width))):
            OvenState.paused,
        Logic(name: 'counter_time_complete')..gets(counter.val.eq(4)):
            OvenState.completed,
      }, actions: [
        led < LEDLight.yellow.value,
        counterReset < 0,
        en < 1,
      ]),
      State<OvenState>(OvenState.paused, events: {
        Logic(name: 'button_resume')
              ..gets(
                  button.eq(Const(Button.resume.value, width: button.width))):
            OvenState.cooking,
      }, actions: [
        led < LEDLight.red.value,
        counterReset < 0,
        en < 0,
      ]),
      State<OvenState>(OvenState.completed, events: {
        Logic(name: 'button_start')
              ..gets(button.eq(Const(Button.start.value, width: button.width))):
            OvenState.cooking,
      }, actions: [
        led < LEDLight.green.value,
        counterReset < 1,
        en < 0,
      ]),
    ];

    _oven =
        FiniteStateMachine<OvenState>(clk, reset, OvenState.standby, states);
  }

  /// The internal [FiniteStateMachine] driving the oven states.
  FiniteStateMachine<OvenState> get ovenStateMachine => _oven;
}
