// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank.dart
// Top-level polyphase FIR filter bank module for the example library.
//
// 2025 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

import 'filter_channel.dart';
import 'filter_controller.dart';
import 'filter_data_interface.dart';
import 'filter_sample.dart';
import 'shared_data_bus.dart';

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

  /// Input [FilterSample] port for channel [ch].
  @protected
  FilterSample samplePin(int ch) => input('sample$ch') as FilterSample;

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
  /// [samples] is a [LogicArray] with one element per channel.
  /// [inputDone] when the input stream is complete.
  ///
  /// Optionally pass [dataBus] (a `LogicNet`) and [writeEnable] to
  /// attach a bidirectional shared data bus via [SharedDataBus].
  /// The bus latches external data when [writeEnable] is low and
  /// drives `storedValue` output.
  FilterBank(
    Logic clk,
    Logic reset,
    Logic start,
    List<FilterSample> samples,
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
    inputDone = addInput('inputDone', inputDone);

    // One typed FilterSample input port per channel.
    final inPorts = <FilterSample>[];
    for (var ch = 0; ch < numChannels; ch++) {
      inPorts.add(addTypedInput('sample$ch', samples[ch]));
    }

    final channelOut = addTypedOutput<LogicArray>(
        'channelOut',
        ({name = 'channelOut'}) =>
            LogicArray([numChannels], dataWidth, name: name));
    final validOut = addOutput('validOut');
    final done = addOutput('done');
    final state = addOutput('state', width: 3);

    // ── Controller FSM ──
    // Drain cycles: numTaps cycles per accumulation + pipeline depth (2) + 1
    final controller = FilterController(
      clk,
      reset,
      start,
      inPorts[0].valid, // valid is shared across channels
      inputDone,
      drainCycles: numTaps + 3,
      name: 'controller',
    );

    final filterEnable = controller.filterEnable;

    // ── Per-channel filter instantiation ──
    final srcIntfs = <FilterDataInterface>[];
    for (var ch = 0; ch < numChannels; ch++) {
      final srcIntf = FilterDataInterface(dataWidth: dataWidth);
      srcIntf.sampleIn <= inPorts[ch].data;
      srcIntf.validIn <= inPorts[ch].valid;

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
