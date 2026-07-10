// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_channel.dart
// Single FIR channel module for the polyphase FIR filter bank example.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/examples/filter_bank/coeff_bank.dart';
import 'package:rohd/src/examples/filter_bank/filter_data_interface.dart';
import 'package:rohd/src/examples/filter_bank/mac_unit.dart';

/// A single polyphase FIR filter channel with [numTaps] taps.
///
/// Uses a [FilterDataInterface] for its sample I/O ports.
///
/// Architecture:
///   - A delay line (shift register) captures incoming samples.
///   - A tap counter cycles 0 … numTaps-1 each sample period.
///   - [CoeffBank] provides the coefficient for the current tap.
///   - A mux selects the delay-line sample for the current tap.
///   - A single [MacUnit] multiplies the selected sample by the
///     coefficient and adds it to a running accumulator.
///   - After all taps are processed the accumulator is latched as
///     the output and the accumulator resets for the next sample.
class FilterChannel extends Module {
  /// The data interface for this channel (internal use only).
  @protected
  late final FilterDataInterface intf;

  /// Filtered output.
  Logic get dataOut => intf.dataOut;

  /// Output valid.
  Logic get validOut => intf.validOut;

  /// Number of FIR taps in this channel.
  final int numTaps;

  /// Bit width of each data sample.
  final int dataWidth;

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Enable input.
  @protected
  Logic get enablePin => input('enable');

  /// Creates a [FilterChannel] with [numTaps] taps at [dataWidth] bits.
  ///
  /// [srcIntf] provides the sample/valid input ports.  [coefficients]
  /// supplies per-tap constant coefficients.
  FilterChannel(
    FilterDataInterface srcIntf,
    Logic clk,
    Logic reset,
    Logic enable, {
    required this.numTaps,
    required this.dataWidth,
    required List<int> coefficients,
    super.name = 'FilterChannel',
  }) : super(definitionName: 'FilterChannel_T${numTaps}_W$dataWidth') {
    // Connect the Interface — creates module input/output ports
    intf = FilterDataInterface(dataWidth: dataWidth)
      ..connectIO(this, srcIntf,
          inputTags: [FilterPortTag.inputPorts],
          outputTags: [FilterPortTag.outputPorts]);

    final sampleIn = intf.sampleIn;
    final validIn = intf.validIn;
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);

    final tapIdxWidth = _bitsFor(numTaps);

    // ── Delay line (shift register via explicit flop bank + gates) ──
    // AND gate: shift enable = enable & validIn & tapCounter==0
    // Samples shift in only when starting a new accumulation cycle.
    final tapCounter = Logic(width: tapIdxWidth, name: 'tapCounter');
    final atFirstTap =
        tapCounter.eq(Const(0, width: tapIdxWidth)).named('atFirstTap');
    final shiftEn = Logic(name: 'shiftEn');
    shiftEn <= (enable & validIn).named('enableAndValid') & atFirstTap;

    // LogicArray-backed delay line: one element per tap register.
    final delayLine = LogicArray([numTaps], dataWidth, name: 'delayLine');
    for (var i = 0; i < numTaps; i++) {
      final tapInput = (i == 0) ? sampleIn : delayLine.elements[i - 1];
      // Mux: hold current value or shift in new sample
      final tapNext = Logic(width: dataWidth, name: 'nextTap$i');
      tapNext <= mux(shiftEn, tapInput, delayLine.elements[i]);
      // Flop: register the next-state value
      delayLine.elements[i] <= flop(clk, reset: reset, tapNext);
    }

    // ── Coefficient bank — driven by tapCounter ──
    // Build a LogicArray of constants from the coefficient list and
    // pass it as an input port to CoeffBank (demonstrates addInputArray
    // on a sub-module).
    final coeffArray = LogicArray([numTaps], dataWidth, name: 'coeffArray');
    for (var i = 0; i < numTaps; i++) {
      coeffArray.elements[i] <= Const(coefficients[i], width: dataWidth);
    }

    final coeffBank = CoeffBank(
      tapCounter,
      coeffArray,
      numTaps: numTaps,
      dataWidth: dataWidth,
      name: 'coeffBank',
    );

    // ── Delay-line mux — select sample for current tap ──
    var selectedSample = delayLine.elements[0];
    for (var i = 1; i < numTaps; i++) {
      final tapSelect =
          tapCounter.eq(Const(i, width: tapIdxWidth)).named('tapSelect$i');
      selectedSample = mux(tapSelect, delayLine.elements[i], selectedSample)
          .named('tapMux$i');
    }

    // ── Running accumulator (feedback register) ──
    final accumReg = Logic(width: dataWidth, name: 'accumReg');
    // Reset accumulator at the start of each new sample (tap 0).
    // Combinational block: equivalent to `always_comb` in SystemVerilog.
    final accumFeedback = Logic(width: dataWidth, name: 'accumFeedback');
    Combinational([
      If(atFirstTap, then: [
        accumFeedback < Const(0, width: dataWidth),
      ], orElse: [
        accumFeedback < accumReg,
      ]),
    ]);

    // ── Single MAC unit — time-multiplexed across taps ──
    final mac = MacUnit(
      selectedSample,
      coeffBank.coeffOut,
      accumFeedback,
      clk,
      reset,
      enable,
      dataWidth: dataWidth,
      name: 'mac',
    );

    // Register the MAC result for accumulator feedback.
    accumReg <= flop(clk, reset: reset, mac.result);

    // ── Tap counter: cycles 0 … numTaps-1 while enabled ──
    // Sequential block: equivalent to `always_ff @(posedge clk)` in SV.
    // When enabled, the counter increments and wraps at numTaps-1.
    // When disabled, it resets to 0.
    final lastTap =
        tapCounter.eq(Const(numTaps - 1, width: tapIdxWidth)).named('lastTap');
    Sequential(clk, reset: reset, [
      If(enable, then: [
        If(lastTap, then: [
          tapCounter < Const(0, width: tapIdxWidth),
        ], orElse: [
          tapCounter < tapCounter + Const(1, width: tapIdxWidth),
        ]),
      ], orElse: [
        tapCounter < Const(0, width: tapIdxWidth),
      ]),
    ]);

    // ── Output latch: capture accumulator when all taps processed ──
    // The MAC pipeline has 2 stages, so the result is ready 2 cycles
    // after the last tap enters.  A 2-stage shift register of lastTap
    // creates the latch strobe.
    final lastTapD1 = Logic(name: 'lastTapD1');
    final lastTapD2 = Logic(name: 'lastTapD2');
    final outputReg = Logic(width: dataWidth, name: 'outputReg');

    // Sequential block with If: latch strobe delay and output register.
    Sequential(clk, reset: reset, [
      lastTapD1 < lastTap,
      lastTapD2 < lastTapD1,
      If(lastTapD2, then: [
        outputReg < accumReg,
      ]),
    ]);

    // ── Valid pipeline: track whether we have a valid output ──
    // validIn is high during data injection.  After the MAC pipeline
    // latency (numTaps + 2 cycles), outputs become valid.
    final validPipe = Logic(name: 'validPipe');
    final outputReady = (lastTapD2 & enable).named('outputReady');

    // Sequential block: register the valid strobe and hold it.
    Sequential(clk, reset: reset, [
      If(enable, then: [
        validPipe < outputReady,
      ]),
    ]);

    // Combinational block: gate the output to zero when not valid.
    final dataOut = intf.dataOut;
    final validOut = intf.validOut;
    Combinational([
      If(validPipe, then: [
        dataOut < outputReg,
      ], orElse: [
        dataOut < Const(0, width: dataWidth),
      ]),
      validOut < validPipe,
    ]);
  }

  /// Minimum bits needed to represent [n] values.
  static int _bitsFor(int n) {
    if (n <= 1) {
      return 1;
    }
    var bits = 0;
    var v = n - 1;
    while (v > 0) {
      bits++;
      v >>= 1;
    }
    return bits;
  }
}
