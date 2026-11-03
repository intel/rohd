// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// serializer_debug.dart
// Minimal debugger demonstration with netlist and live waveform services.
//
// 2026 October 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

import 'serializer/serializer.dart';

/// Runs a clocked design with netlist and live waveform debugging.
Future<void> main() async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final load = Logic(name: 'load');
  final parallelData = Logic(name: 'parallelData', width: 8);
  final dut = Serializer(clk, reset, load, parallelData);
  await dut.build();

  NetlistService(dut);
  WaveformService(dut, enableDevToolsStreaming: true);

  await simulateSerializer(
    clk: clk,
    reset: reset,
    load: load,
    parallelData: parallelData,
  );
}
