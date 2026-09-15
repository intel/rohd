// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_debug.dart
// Comprehensive fixture generator for the FilterBank example.
//
// 2026 May 3
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//
// Produces all artifacts needed for debug and devtools validation:
//   - SystemVerilog files (.sv)
//   - FLC cross-probing data (.flc.json, .flc.html)
//   - Netlist / schematic JSON (.rohd.json)
//   - VCD waveforms (.vcd)
//   - Signal source trace reports (.txt, .html)
//
// Usage:
//   dart run example/filter_bank_debug.dart
//
// 2026 May 3
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';

import 'filter_bank/filter_bank_modules.dart';

const _outDir = 'build/filter_bank_debug';

Future<void> main() async {
  const dataWidth = 16;
  const numTaps = 3;
  const coeffs0 = [1, 2, 1]; // channel 0: symmetric LPF kernel
  const coeffs1 = [1, -2, 1]; // channel 1: high-pass kernel

  // ── Enable tracing before anything else ──
  SourceTracer.activate();

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

  await dut.build();

  final dir = Directory(_outDir)..createSync(recursive: true);
  final packageRoot = Directory.current.path;

  // ── 1. SystemVerilog ──
  final sv = SystemVerilogService(dut, register: false)..writeFiles(_outDir);

  // ── 2. FLC cross-probing (TraceService) ──
  final trace = TraceService(
    dut,
    svService: sv,
    packageRoot: packageRoot,
    register: false,
  );
  if (trace.hasTraces) {
    trace
      ..writeFlcFiles(_outDir)
      ..writeFlcHtml(_outDir);
  }

  // ── 3. Signal source trace reports ──
  final report = SourceTracer.hierarchyReport(dut, packageRoot: packageRoot);
  File('${dir.path}/traces.txt').writeAsStringSync(report);

  final editorReport = SourceTracer.hierarchyReport(
    dut,
    packageRoot: packageRoot,
    useFileUris: true,
  );
  File('${dir.path}/traces_editor.txt').writeAsStringSync(editorReport);

  final htmlReport = SourceTracer.htmlReport(dut, packageRoot: packageRoot);
  File('${dir.path}/traces.html').writeAsStringSync(htmlReport);

  // ── 4. Netlist / schematic JSON ──
  final netlist = NetlistService(dut, packageRoot: packageRoot);
  File('${dir.path}/${dut.definitionName}.rohd.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(jsonDecode(netlist.json)),
  );

  // ── 5. Waveform simulation ──
  Simulator.setMaxSimTime(500);
  WaveformService.fromOutputPath(
    dut,
    outputPath: '${dir.path}/filter_bank.vcd',
  );

  unawaited(Simulator.run());

  // Reset sequence
  reset.inject(1);
  start.inject(0);
  samples[0].data.inject(0);
  samples[1].data.inject(0);
  samples[0].valid.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(0);

  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);

  // Start filtering
  await clk.nextPosedge;
  start.inject(1);
  await clk.nextPosedge;
  start.inject(0);
  samples[0].valid.inject(1);
  samples[1].valid.inject(1);

  // Impulse response: single '1' then zeros
  samples[0].data.inject(1);
  samples[1].data.inject(1);
  await clk.nextPosedge;

  for (var i = 0; i < 4; i++) {
    samples[0].data.inject(0);
    samples[1].data.inject(0);
    await clk.nextPosedge;
  }

  // Step response: hold '100' for several cycles
  for (var i = 0; i < 4; i++) {
    samples[0].data.inject(100);
    samples[1].data.inject(100);
    await clk.nextPosedge;
  }

  // Ramp: increasing values
  for (var i = 0; i < 4; i++) {
    samples[0].data.inject(i * 50);
    samples[1].data.inject(i * 50);
    await clk.nextPosedge;
  }

  // Back to zeros
  for (var i = 0; i < 4; i++) {
    samples[0].data.inject(0);
    samples[1].data.inject(0);
    await clk.nextPosedge;
  }

  // Signal end of input
  samples[0].valid.inject(0);
  samples[1].valid.inject(0);
  inputDone.inject(1);
  await clk.nextPosedge;
  inputDone.inject(0);

  // Wait for drain
  for (var i = 0; i < 15; i++) {
    await clk.nextPosedge;
  }

  await Simulator.endSimulation();
}
