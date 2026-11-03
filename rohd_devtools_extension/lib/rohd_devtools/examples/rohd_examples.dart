// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_examples.dart
// In-process ROHD example designs for loopback mode.
//
// Each example builds a real ROHD module, initializes in-memory hierarchy and
// waveform services, runs simulation, and keeps the event loop alive so the
// DevTools UI can query data via direct calls.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rohd/examples.dart';
import 'package:rohd/rohd.dart';

/// Descriptor for a launchable in-process ROHD example.
class RohdExample {
  /// Human-readable display name.
  final String name;

  /// Async function that builds, simulates, and keeps alive.
  ///
  /// Returns a [Completer] that the shell can complete to shut down the
  /// example (e.g. when switching examples or disconnecting).
  final Future<Completer<void>> Function() launcher;

  /// Creates a launchable in-process ROHD example descriptor.
  const RohdExample({required this.name, required this.launcher});
}

/// All available in-process ROHD examples.
///
/// Add new entries here and they'll appear in the demo-mode picker.
final rohdExamples = [
  const RohdExample(name: 'Counter (8-bit)', launcher: launchCounter),
  const RohdExample(name: 'Oven FSM', launcher: launchOvenFsm),
  const RohdExample(name: 'Tree (8×8-bit max)', launcher: launchTree),
  const RohdExample(name: 'FilterBank', launcher: launchFilterBank),
];

/// Initializes the in-memory services used by an in-process DevTools example.
///
/// The browser cannot create the VCD file used by [Module.dumpWaves], so these
/// examples record waveform data directly in [WaveformDataService] instead.
void _initializeInProcessServices(Module module) {
  WaveformDataService.instance.clear();
  NetlistService(module);
  WaveformDataService.init(module);
  WaveformDataService.instance.startRecording();
}

// ---------------------------------------------------------------------------
// Counter example
// ---------------------------------------------------------------------------

/// An 8-bit counter with enable and reset.
class _Counter extends Module {
  Logic get val => output('val');

  final int width;

  _Counter(Logic en, Logic reset, Logic clk)
      : width = 8,
        super(name: 'counter', definitionName: 'Counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    clk = addInput('clk', clk);
    addOutput('val', width: width);

    val <= flop(clk, reset: reset, en: en, val + 1);
  }
}

/// Build, simulate, and keep alive an 8-bit counter.
///
/// Build, simulate, and keep alive an 8-bit counter.
///
/// Runs the simulation for 200 time units (~20 clock cycles) so the
/// waveform viewer has real data to display, then keeps the process alive
/// so hierarchy and waveform queries continue to work.
///
/// The simulation does NOT call [Simulator.endSimulation] — the simulator
/// remains in a runnable state so additional cycles can be triggered later.
Future<Completer<void>> launchCounter() async {
  // Reset the simulator to a clean state (important when switching
  // between examples without restarting the process).
  await Simulator.reset();

  final en = Logic(name: 'en');
  final reset = Logic(name: 'reset');
  final clk = SimpleClockGenerator(10).clk;

  final counter = _Counter(en, reset, clk);

  await counter.build();
  _initializeInProcessServices(counter);

  debugPrint(
    '[RohdExample] Counter built — '
    'WaveformDataService initialized: '
    '${WaveformDataService.instance.isInitialized}, '
    'signals: ${WaveformDataService.instance.signalCount}',
  );

  // Start simulation — runs via microtasks, yielding between ticks.
  unawaited(Simulator.run());

  // Reset sequence.
  en.inject(0);
  reset.inject(1);

  await clk.nextPosedge;
  await clk.nextPosedge;

  // Release reset, enable counter.
  reset.inject(0);
  en.inject(1);

  // Let the counter run for 200 time units (~20 clock cycles).
  // setMaxSimTime causes the simulator to stop at time 200 but does NOT
  // tear down the simulator state, so data remains queryable.
  Simulator.setMaxSimTime(200);
  await Simulator.simulationEnded;

  debugPrint(
    '[RohdExample] Counter simulation complete — '
    'time=${WaveformDataService.instance.currentTime}, '
    'changes=${WaveformDataService.instance.totalValueChanges}',
  );

  // Keep the process alive until the shell says stop.
  final keepAlive = Completer<void>();
  return keepAlive;
}

// ---------------------------------------------------------------------------
// Oven FSM example
// ---------------------------------------------------------------------------

/// Build, simulate, and keep alive a microwave oven FSM.
///
/// Stimulus: reset → start cooking → pause → resume → cook until timer
/// completes → restart.  ~300 time units of waveform data.
Future<Completer<void>> launchOvenFsm() async {
  await Simulator.reset();

  final button = Logic(name: 'button', width: 2);
  final reset = Logic(name: 'reset');
  final clk = SimpleClockGenerator(10).clk;

  final oven = OvenModule(button, reset, clk);

  await oven.build();
  _initializeInProcessServices(oven);

  debugPrint(
    '[RohdExample] OvenFSM built — '
    'WaveformDataService initialized: '
    '${WaveformDataService.instance.isInitialized}, '
    'signals: ${WaveformDataService.instance.signalCount}',
  );

  unawaited(Simulator.run());

  // ── Reset ──
  reset.inject(1);
  button.inject(Button.start.value);

  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);

  // ── Start cooking ──
  button.inject(Button.start.value);
  await clk.nextPosedge;
  await clk.nextPosedge;
  await clk.nextPosedge;

  // ── Pause ──
  button.inject(Button.pause.value);
  await clk.nextPosedge;
  await clk.nextPosedge;
  await clk.nextPosedge;

  // ── Resume ──
  button.inject(Button.resume.value);

  // Let the counter run until it completes (counter reaches 4 → done)
  for (var i = 0; i < 8; i++) {
    await clk.nextPosedge;
  }

  // ── Restart from completed state ──
  button.inject(Button.start.value);
  await clk.nextPosedge;
  await clk.nextPosedge;

  Simulator.setMaxSimTime(300);
  await Simulator.simulationEnded;

  debugPrint(
    '[RohdExample] OvenFSM simulation complete — '
    'time=${WaveformDataService.instance.currentTime}, '
    'changes=${WaveformDataService.instance.totalValueChanges}',
  );

  final keepAlive = Completer<void>();
  return keepAlive;
}

// ---------------------------------------------------------------------------
// Tree of Two-Input Modules example
// ---------------------------------------------------------------------------

/// A clocked wrapper around [TreeOfTwoInputModules] that samples
/// combinational inputs on each rising edge for waveform visibility.
class _ClockedTree extends Module {
  Logic get out => output('out');

  _ClockedTree(List<Logic> inputs, Logic clk)
      : super(name: 'clocked_tree', definitionName: 'ClockedTree') {
    clk = addInput('clk', clk);
    final registered = <Logic>[];
    for (var i = 0; i < inputs.length; i++) {
      final inp = addInput('in$i', inputs[i], width: inputs[i].width);
      final reg = Logic(width: inp.width, name: 'reg$i');
      reg <= flop(clk, inp);
      registered.add(reg);
    }

    final tree = TreeOfTwoInputModules(registered, (a, b) => mux(a > b, a, b));

    addOutput('out', width: registered[0].width);
    out <= tree.out;
  }
}

/// Build, simulate, and keep alive a tree-max module with 8 inputs.
///
/// Injects different values each cycle so the waveform shows the tree
/// selecting the maximum.  ~200 time units of waveform data.
Future<Completer<void>> launchTree() async {
  await Simulator.reset();

  const width = 8;
  const count = 8;

  final clk = SimpleClockGenerator(10).clk;
  final inputs = List<Logic>.generate(
    count,
    (i) => Logic(name: 'in$i', width: width),
  );

  final tree = _ClockedTree(inputs, clk);

  await tree.build();
  _initializeInProcessServices(tree);

  debugPrint(
    '[RohdExample] Tree built — '
    'WaveformDataService initialized: '
    '${WaveformDataService.instance.isInitialized}, '
    'signals: ${WaveformDataService.instance.signalCount}',
  );

  unawaited(Simulator.run());

  // Inject varying values each cycle so the max output changes.
  for (var cycle = 0; cycle < 20; cycle++) {
    for (var i = 0; i < count; i++) {
      // Rotating pattern: each input gets a different value per cycle.
      inputs[i].inject((cycle * 17 + i * 37) % 256);
    }
    await clk.nextPosedge;
  }

  Simulator.setMaxSimTime(200);
  await Simulator.simulationEnded;

  debugPrint(
    '[RohdExample] Tree simulation complete — '
    'time=${WaveformDataService.instance.currentTime}, '
    'changes=${WaveformDataService.instance.totalValueChanges}',
  );

  final keepAlive = Completer<void>();
  return keepAlive;
}

// ---------------------------------------------------------------------------
// FilterBank example (with bidirectional bus)
// ---------------------------------------------------------------------------

/// Build, simulate, and keep alive a 2-channel FIR filter bank with
/// bidirectional `dataBus` (LogicNet / inOut port) and `writeEnable`
/// exercising the SharedDataBus sub-module.
///
/// An external [TriStateBuffer] drives the bus when `writeEnable` is low
/// (external write); the internal SharedDataBus drives it when high
/// (module read-back).
///
/// Runs an impulse-response test: reset → bus exercise → start →
/// single '1' sample on both channels → zeros → inputDone → drain.
/// ~500 time units of waveform data.
Future<Completer<void>> launchFilterBank() async {
  await Simulator.reset();

  const dataWidth = 16;
  const numTaps = 3;
  const coeffs0 = [1, 2, 1];
  const coeffs1 = [1, -2, 1];

  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samples = List.generate(2, (ch) => FilterSample(name: r'sample$ch'));
  final inputDone = Logic(name: 'inputDone');
  final dataBus = LogicNet(name: 'dataBus', width: dataWidth);
  final writeEnable = Logic(name: 'writeEnable');

  // External driver: a TriStateBuffer that drives the bus when the module
  // is NOT driving (writeEnable == 0 → external owns the bus).
  final extData = Logic(name: 'extData', width: dataWidth);
  final extDriver = TriStateBuffer(
    extData,
    enable: ~writeEnable,
    name: 'extBusDriver',
  );
  extDriver.out.gets(dataBus);

  final dut = FilterBank(
    clk,
    reset,
    start,
    samples,
    inputDone,
    numTaps: numTaps,
    dataWidth: dataWidth,
    coefficients: [coeffs0, coeffs1],
    dataBus: dataBus,
    writeEnable: writeEnable,
  );

  await dut.build();
  _initializeInProcessServices(dut);

  debugPrint(
    '[RohdExample] FilterBank built — '
    'WaveformDataService initialized: '
    '${WaveformDataService.instance.isInitialized}, '
    'signals: ${WaveformDataService.instance.signalCount}',
  );

  unawaited(Simulator.run());

  // ── Reset ──
  reset.inject(1);
  start.inject(0);
  samples[0].data.inject(0);
  samples[1].data.inject(0);
  samples[0].valid.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(0);
  writeEnable.inject(0);
  extData.inject(0);

  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);

  // ── External write onto the bus (writeEnable=0 → ext driver active) ──
  extData.inject(0xABCD);
  await clk.nextPosedge;
  await clk.nextPosedge;

  // ── Module reads back stored value (writeEnable=1 → internal driver) ──
  writeEnable.inject(1);
  await clk.nextPosedge;
  await clk.nextPosedge;
  writeEnable.inject(0);

  // ── External writes another value ──
  extData.inject(0x1234);
  await clk.nextPosedge;
  await clk.nextPosedge;

  // ── Start filtering (same stimulus as plain FilterBank) ──
  extData.inject(0);
  await clk.nextPosedge;
  start.inject(1);
  await clk.nextPosedge;
  start.inject(0);
  samples[0].valid.inject(1);
  samples[1].valid.inject(1);

  samples[0].data.inject(1);
  samples[1].data.inject(1);
  await clk.nextPosedge;

  for (var i = 0; i < 8; i++) {
    samples[0].data.inject(0);
    samples[1].data.inject(0);
    await clk.nextPosedge;
  }

  // ── End of input ──
  samples[0].valid.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(1);
  await clk.nextPosedge;
  inputDone.inject(0);

  // ── Drain pipeline ──
  Simulator.setMaxSimTime(500);
  await Simulator.simulationEnded;

  debugPrint(
    '[RohdExample] FilterBank simulation complete — '
    'time=${WaveformDataService.instance.currentTime}, '
    'changes=${WaveformDataService.instance.totalValueChanges}',
  );

  final keepAlive = Completer<void>();
  return keepAlive;
}
