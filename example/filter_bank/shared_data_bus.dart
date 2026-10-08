// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// shared_data_bus.dart
// Bidirectional data bus module for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// A module with a bidirectional data bus for loading/reading data.
///
/// In real hardware, a shared data bus is common for:
///   - Loading filter coefficients from external memory
///   - Reading diagnostic status or filter output snapshots
///
/// Direction is controlled by `writeEnable`: when high, the module's
/// internal [TriStateBuffer] drives `storedValue` onto `dataBus`;
/// when low, the external driver owns the bus and the module latches
/// the incoming value into a register.
///
/// Exercises `addInOut` / `LogicNet` / [TriStateBuffer] / inout port
/// direction through the full ROHD stack: synthesis, hierarchy,
/// waveform capture, and DevTools rendering.
class SharedDataBus extends Module {
  /// The bidirectional data bus port.
  Logic get dataBus => inOut('dataBus');

  /// The stored value (latched when the bus is driven externally).
  Logic get storedValue => output('storedValue');

  /// Write-enable input.
  @protected
  Logic get writeEnablePin => input('writeEnable');

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Data width in bits.
  final int dataWidth;

  /// Creates a [SharedDataBus] with a [dataWidth]-bit bidirectional port.
  ///
  /// [dataBusNet] is the external [LogicNet] to connect.
  /// [writeEnable] controls bus direction: 1 = module drives bus,
  /// 0 = external drives bus (module reads).
  /// [clk] and [reset] provide synchronous storage.
  SharedDataBus(
    LogicNet dataBusNet,
    Logic writeEnable,
    Logic clk,
    Logic reset, {
    required this.dataWidth,
    super.name = 'SharedDataBus',
  }) : super(definitionName: 'SharedDataBus') {
    final bus = addInOut('dataBus', dataBusNet, width: dataWidth);
    writeEnable = addInput('writeEnable', writeEnable);
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    final storedValue = addOutput('storedValue', width: dataWidth);

    // Latch the bus value on clock edge when the external side is driving.
    storedValue <=
        flop(
          clk,
          bus,
          reset: reset,
          en: ~writeEnable,
          resetValue: Const(0, width: dataWidth),
        );

    // Drive the latched value back onto the bus when writeEnable is high.
    // TriStateBuffer drives its out (a LogicNet) with storedValue when
    // enabled; otherwise it outputs high-Z.  Joining out↔bus makes the
    // two nets share the same wire.
    TriStateBuffer(storedValue, enable: writeEnable, name: 'busDriver')
        .out
        .gets(bus);
  }
}
