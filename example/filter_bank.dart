// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank.dart
// A polyphase FIR filter bank design example exercising:
//   - Deep hierarchy with shared sub-module definitions
//   - Interface (FilterDataInterface)
//   - LogicStructure (FilterSample)
//   - LogicArray (coefficient storage)
//   - Pipeline (pipelined MAC accumulation)
//   - FiniteStateMachine (FilterController)
//
// The filter bank has two channels that share an identical MacUnit definition.
// A controller FSM sequences: idle → loading → running → draining → done.
//
// 2026 March 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';

// Import module definitions.
import 'package:rohd/src/examples/filter_bank_modules.dart';

// Re-export so downstream consumers (e.g. devtools loopback) can use.
export 'package:rohd/src/examples/filter_bank_modules.dart';

// ──────────────────────────────────────────────────────────────────
// Standalone simulation entry point
// ──────────────────────────────────────────────────────────────────

Future<void> main({bool noPrint = false}) async {
  const dataWidth = 16;
  const numTaps = 3;

  // Low-pass-ish coefficients (scaled integers)
  const coeffs0 = [1, 2, 1]; // channel 0: symmetric LPF kernel
  const coeffs1 = [1, -2, 1]; // channel 1: high-pass kernel

  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
  final inputDone = Logic(name: 'inputDone');

  final dut = FilterBank(
    clk,
    reset,
    start,
    samples,
    inputDone,
    numTaps: numTaps,
    dataWidth: dataWidth,
    coefficients: [coeffs0, coeffs1],
  );

  // Before we can simulate or generate code, we need to build it.
  await dut.build();

  // Set a maximum time for the simulation so it doesn't keep running forever.
  Simulator.setMaxSimTime(500);

  // Attach a waveform dumper so we can see what happens.
  if (!noPrint) {
    WaveDumper(dut, outputPath: 'filter_bank.vcd');
  }

  // Kick off the simulation.
  unawaited(Simulator.run());

  // ── Reset ──
  reset.inject(1);
  start.inject(0);
  samples[0].data.inject(0);
  samples[0].valid.inject(0);
  samples[1].data.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(0);

  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);

  // ── Start filtering ──
  await clk.nextPosedge;
  start.inject(1);
  await clk.nextPosedge;
  start.inject(0);
  samples[0].valid.inject(1);
  samples[1].valid.inject(1);

  // ── Feed sample stream: impulse response test ──
  // Send a single '1' followed by zeros to get the impulse response
  samples[0].data.inject(1);
  samples[1].data.inject(1);
  await clk.nextPosedge;

  for (var i = 0; i < 8; i++) {
    samples[0].data.inject(0);
    samples[1].data.inject(0);
    await clk.nextPosedge;
  }

  // ── Signal end of input ──
  samples[0].valid.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(1);
  await clk.nextPosedge;
  inputDone.inject(0);

  // ── Wait for drain ──
  for (var i = 0; i < 15; i++) {
    await clk.nextPosedge;
  }

  await Simulator.endSimulation();
}
