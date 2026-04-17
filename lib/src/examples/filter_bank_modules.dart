// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_modules.dart
// Module class definitions for the polyphase FIR filter bank example.
//
// Architecture: each FilterChannel uses a single MacUnit that is
// time-multiplexed across taps.  A tap counter sequences CoeffBank
// and a delay-line mux so the MAC accumulates one tap per clock cycle.
// After numTaps cycles the accumulated result is latched as the output
// sample and the accumulator resets for the next input sample.
//
// ROHD features exercised:
//   - LogicStructure (FilterSample)
//   - Interface (FilterDataInterface)
//   - LogicArray (CoeffBank coefficient ROM, delay line)
//   - Pipeline (MacUnit multiply-accumulate)
//   - FiniteStateMachine (FilterController)
//   - Multiple instantiation (two FilterChannels share one definition)
//
// Separated from filter_bank.dart so these classes can be imported
// in web-targeted code (no dart:io dependency).
//
// 2026 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

// ──────────────────────────────────────────────────────────────────
// LogicStructure: a typed sample word carrying data + valid + channel
// ──────────────────────────────────────────────────────────────────

/// A structured signal bundling a data sample with metadata.
///
/// Packs three fields — [data], [valid], and [channel] — into a single
/// bus that can be driven and sampled as a unit.  Used throughout the
/// [FilterBank] to carry tagged samples between modules.
class FilterSample extends LogicStructure {
  /// The sample data word.
  late final Logic data;

  /// Whether this sample is valid.
  late final Logic valid;

  /// The channel index this sample belongs to.
  late final Logic channel;

  /// Creates a [FilterSample] with the given [dataWidth] (default 16)
  /// and optional [name].
  FilterSample({int dataWidth = 16, String? name})
      : super(
          [
            Logic(name: 'data', width: dataWidth),
            Logic(name: 'valid'),
            Logic(name: 'channel'),
          ],
          name: name ?? 'filter_sample',
        ) {
    data = elements[0];
    valid = elements[1];
    channel = elements[2];
  }

  // Private constructor for clone to share element structure.
  FilterSample._clone(super.elements, {required super.name}) {
    data = elements[0];
    valid = elements[1];
    channel = elements[2];
  }

  @override

  /// Returns a structural clone of this sample, preserving element names.
  FilterSample clone({String? name}) => FilterSample._clone(
        elements.map((e) => e.clone(name: e.name)),
        name: name ?? this.name,
      );
}

// ──────────────────────────────────────────────────────────────────
// Interface: tagged port bundle for filter data I/O
// ──────────────────────────────────────────────────────────────────

/// Tags for grouping port directions in [FilterDataInterface].
enum FilterPortTag {
  /// Ports carrying data into the filter (`sampleIn`, `validIn`).
  inputPorts,

  /// Ports carrying data out of the filter (`dataOut`, `validOut`).
  outputPorts,
}

/// An interface carrying sample data and control into/out of filter modules.
///
/// Groups ports by [FilterPortTag] so that [connectIO] can wire
/// inputs and outputs in a single call.
class FilterDataInterface extends Interface<FilterPortTag> {
  /// Input sample data bus.
  Logic get sampleIn => port('sampleIn');

  /// Input valid strobe.
  Logic get validIn => port('validIn');

  /// Output filtered data bus.
  Logic get dataOut => port('dataOut');

  /// Output valid strobe.
  Logic get validOut => port('validOut');

  /// The data width used by this interface.
  final int _dataWidth;

  /// Creates a [FilterDataInterface] with the given [dataWidth]
  /// (default 16 bits).
  FilterDataInterface({int dataWidth = 16}) : _dataWidth = dataWidth {
    setPorts([
      Logic.port('sampleIn', dataWidth),
      Logic.port('validIn'),
    ], [
      FilterPortTag.inputPorts
    ]);

    setPorts([
      Logic.port('dataOut', dataWidth),
      Logic.port('validOut'),
    ], [
      FilterPortTag.outputPorts
    ]);
  }

  @override

  /// Returns a new interface with the same data width.
  FilterDataInterface clone() => FilterDataInterface(dataWidth: _dataWidth);
}

// ──────────────────────────────────────────────────────────────────
// CoeffBank: stores FIR tap coefficients in a LogicArray
// ──────────────────────────────────────────────────────────────────

/// A coefficient storage module backed by a [LogicArray] input port.
///
/// Accepts a [LogicArray] of per-tap coefficients via [addInputArray]
/// and a tap index, then mux-selects the corresponding coefficient.
class CoeffBank extends Module {
  /// The coefficient value at the selected index.
  Logic get coeffOut => output('coeffOut');

  /// The per-tap coefficient array (registered input port).
  @protected
  LogicArray get coeffArray => input('coeffArray') as LogicArray;

  /// The tap index input.
  @protected
  Logic get tapIndex => input('tapIndex');

  /// Number of taps.
  final int numTaps;

  /// Data width.
  final int dataWidth;

  /// Creates a [CoeffBank] with [numTaps] taps at [dataWidth] bits.
  ///
  /// [coefficients] is a [LogicArray] with one element per tap —
  /// registered as an input port via [addInputArray].
  /// [tapIndex] selects the active coefficient.
  CoeffBank(Logic tapIndex, LogicArray coefficients,
      {required this.numTaps,
      required this.dataWidth,
      super.name = 'CoeffBank'})
      : super(definitionName: 'CoeffBank_T${numTaps}_W$dataWidth') {
    // Register ports
    tapIndex = addInput('tapIndex', tapIndex, width: tapIndex.width);
    final coeffArray = addInputArray('coeffArray', coefficients,
        dimensions: [numTaps], elementWidth: dataWidth);
    final coeffOut = addOutput('coeffOut', width: dataWidth);

    // Mux-chain ROM: priority-select coefficient by tap index.
    Logic selected = Const(0, width: dataWidth);
    for (var i = numTaps - 1; i >= 0; i--) {
      selected = mux(
        tapIndex.eq(Const(i, width: tapIndex.width)).named('tapMatch$i'),
        coeffArray.elements[i],
        selected,
      );
    }
    coeffOut <= selected;
  }
}

// ──────────────────────────────────────────────────────────────────
// MacUnit: a single multiply-accumulate pipeline stage
// ──────────────────────────────────────────────────────────────────

/// A pipelined multiply-accumulate unit.
///
/// Pipeline stage 0: multiply sample × coefficient
/// Pipeline stage 1: add product to running accumulator
class MacUnit extends Module {
  /// Accumulated result.
  Logic get result => output('result');

  /// Sample data input.
  @protected
  Logic get sampleInPin => input('sampleIn');

  /// Coefficient input.
  @protected
  Logic get coeffInPin => input('coeffIn');

  /// Accumulator input.
  @protected
  Logic get accumInPin => input('accumIn');

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Enable input.
  @protected
  Logic get enablePin => input('enable');

  /// Data width.
  final int dataWidth;

  /// Creates a [MacUnit] that multiplies [sampleIn] by [coeffIn] in
  /// stage 0 and adds the product to [accumIn] in stage 1.
  ///
  /// [clk], [reset], and [enable] control the pipeline registers.
  MacUnit(Logic sampleIn, Logic coeffIn, Logic accumIn, Logic clk, Logic reset,
      Logic enable,
      {required this.dataWidth, super.name = 'MacUnit'})
      : super(definitionName: 'MacUnit_W$dataWidth') {
    sampleIn = addInput('sampleIn', sampleIn, width: dataWidth);
    coeffIn = addInput('coeffIn', coeffIn, width: dataWidth);
    accumIn = addInput('accumIn', accumIn, width: dataWidth);
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    enable = addInput('enable', enable);
    final result = addOutput('result', width: dataWidth);

    // A 2-stage pipeline: multiply, then accumulate
    final pipe = Pipeline(
      clk,
      reset: reset,
      stages: [
        // Stage 0: multiply
        (p) => [
              // Product = sample * coefficient (truncated to dataWidth)
              p.get(sampleIn) <
                  (p.get(sampleIn) * p.get(coeffIn)).named('product'),
            ],
        // Stage 1: accumulate
        (p) => [
              p.get(sampleIn) <
                  (p.get(sampleIn) + p.get(accumIn)).named('macSum'),
            ],
      ],
      signals: [sampleIn, coeffIn, accumIn],
    );

    result <= pipe.get(sampleIn);
  }
}

// ──────────────────────────────────────────────────────────────────
// FilterChannel: one polyphase FIR channel with time-multiplexed MAC
// ──────────────────────────────────────────────────────────────────

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

// ──────────────────────────────────────────────────────────────────
// FilterController: FSM sequencing the filter bank
// ──────────────────────────────────────────────────────────────────

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

// ──────────────────────────────────────────────────────────────────
// FilterBank: top-level 2-channel polyphase FIR filter
// ──────────────────────────────────────────────────────────────────

/// A 2-channel polyphase FIR filter bank.
///
/// Hierarchy:
/// ```text
/// FilterBank (top)
/// ├── FilterController (FSM)
/// ├── FilterChannel 'ch0'
/// │   ├── CoeffBank (coefficient ROM via LogicArray + mux chain)
/// │   └── MacUnit 'mac' (pipelined multiply-accumulate)
/// └── FilterChannel 'ch1'
///     ├── CoeffBank
///     └── MacUnit 'mac'
/// ```
///
/// Each channel time-multiplexes a single MacUnit across all taps,
/// sequenced by a tap counter that drives the CoeffBank tap index
/// and a delay-line sample mux.
///
/// Uses:
///   - [FilterDataInterface] for I/O port bundles
///   - [FilterSample] LogicStructure for structured sample signals
///   - [LogicArray] in CoeffBank for coefficient storage
///   - [Pipeline] in MacUnit for pipelined MAC
///   - [FiniteStateMachine] in FilterController for sequencing
///   - Multiple instantiation: two [FilterChannel]s share one definition
///   - [LogicNet] / [addInOut] for bidirectional shared data bus

// ──────────────────────────────────────────────────────────────────
// SharedDataBus: bidirectional port for coefficient/status I/O
// ──────────────────────────────────────────────────────────────────

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

/// The top-level polyphase FIR filter bank.
class FilterBank extends Module {
  /// Per-channel filtered outputs as a [LogicArray].
  ///
  /// `channelOut.elements[i]` is the filtered output of channel `i`.
  LogicArray get channelOut => output('channelOut') as LogicArray;

  /// Channel 0 filtered output (convenience getter).
  Logic get out0 => channelOut.elements[0];

  /// Channel 1 filtered output (convenience getter).
  Logic get out1 => channelOut.elements[1];

  /// Output valid (aligned with filtered outputs).
  Logic get validOut => output('validOut');

  /// Done signal from the controller FSM.
  Logic get done => output('done');

  /// Controller state (for debug visibility).
  Logic get state => output('state');

  /// Clock input.
  @protected
  Logic get clkPin => input('clk');

  /// Reset input.
  @protected
  Logic get resetPin => input('reset');

  /// Start input.
  @protected
  Logic get startPin => input('start');

  /// Per-channel sample input array.
  @protected
  LogicArray get samplesInPin => input('samplesIn') as LogicArray;

  /// Input valid strobe.
  @protected
  Logic get validInPin => input('validIn');

  /// Input-done strobe.
  @protected
  Logic get inputDonePin => input('inputDone');

  /// Number of FIR taps per channel.
  final int numTaps;

  /// Bit width of each data sample.
  final int dataWidth;

  /// Number of filter channels.
  final int numChannels;

  /// Creates a [FilterBank] with [numChannels] channels (default 2).
  ///
  /// Each channel has [numTaps] FIR taps at [dataWidth] bits.
  /// [coefficients] is a list of per-channel coefficient lists —
  /// `coefficients[i]` supplies the tap weights for channel `i`.
  /// [samplesIn] is a [LogicArray] with one element per channel.
  /// [validIn] qualifies the sample data. Assert [start] to begin
  /// and [inputDone] when the input stream is complete.
  ///
  /// Optionally pass [dataBus] (a `LogicNet`) and [writeEnable] to
  /// attach a bidirectional shared data bus via [SharedDataBus].
  /// The bus latches external data when [writeEnable] is low and
  /// drives `storedValue` output.
  FilterBank(
    Logic clk,
    Logic reset,
    Logic start,
    LogicArray samplesIn,
    Logic validIn,
    Logic inputDone, {
    required this.numTaps,
    required this.dataWidth,
    required List<List<int>> coefficients,
    this.numChannels = 2,
    LogicNet? dataBus,
    Logic? writeEnable,
    super.name = 'FilterBank',
    String? definitionName,
  }) : super(definitionName: definitionName ?? 'FilterBank') {
    if (coefficients.length != numChannels) {
      throw Exception(
          'coefficients must have $numChannels entries (one per channel).');
    }

    // ── Register ports ──
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    start = addInput('start', start);
    samplesIn = addInputArray('samplesIn', samplesIn,
        dimensions: [numChannels], elementWidth: dataWidth);
    validIn = addInput('validIn', validIn);
    inputDone = addInput('inputDone', inputDone);

    final channelOut = addOutputArray('channelOut',
        dimensions: [numChannels], elementWidth: dataWidth);
    final validOut = addOutput('validOut');
    final done = addOutput('done');
    final state = addOutput('state', width: 3);

    // ── FilterSample LogicStructure for input bundling ──
    final samples = <FilterSample>[];
    for (var ch = 0; ch < numChannels; ch++) {
      final sample = FilterSample(dataWidth: dataWidth, name: 'sample$ch');
      sample.data <= samplesIn.elements[ch];
      sample.valid <= validIn;
      sample.channel <= Const(ch);
      samples.add(sample);
    }

    // ── Controller FSM ──
    // Drain cycles: numTaps cycles per accumulation + pipeline depth (2) + 1
    final controller = FilterController(
      clk,
      reset,
      start,
      validIn,
      inputDone,
      drainCycles: numTaps + 3,
      name: 'controller',
    );

    final filterEnable = controller.filterEnable;

    // ── Per-channel filter instantiation ──
    final srcIntfs = <FilterDataInterface>[];
    for (var ch = 0; ch < numChannels; ch++) {
      final srcIntf = FilterDataInterface(dataWidth: dataWidth);
      srcIntf.sampleIn <= samples[ch].data;
      srcIntf.validIn <= samples[ch].valid;

      FilterChannel(
        srcIntf,
        clk,
        reset,
        filterEnable,
        numTaps: numTaps,
        dataWidth: dataWidth,
        coefficients: coefficients[ch],
        name: 'ch$ch',
      );

      srcIntfs.add(srcIntf);
    }

    // ── Connect outputs ──
    for (var ch = 0; ch < numChannels; ch++) {
      channelOut.elements[ch] <= srcIntfs[ch].dataOut;
    }
    validOut <= srcIntfs[0].validOut;
    done <= controller.doneFlag;
    state <= controller.state;

    // ── Optional shared data bus (inOut port) ──
    if (dataBus != null && writeEnable != null) {
      final busPort = addInOut('dataBus', dataBus, width: dataWidth);
      writeEnable = addInput('writeEnable', writeEnable);
      final storedValue = addOutput('storedValue', width: dataWidth);

      final sharedBus = SharedDataBus(
        LogicNet(name: 'busNet', width: dataWidth)..gets(busPort),
        writeEnable,
        clk,
        reset,
        dataWidth: dataWidth,
      );
      storedValue <= sharedBus.storedValue;
    }
  }
}
