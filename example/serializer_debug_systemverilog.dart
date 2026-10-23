// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// serializer_debug_systemverilog.dart
// Debugger demonstration with SystemVerilog output and source cross-probing.
//
// 2026 October 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';

import 'serializer/serializer.dart';

/// Adds generated SystemVerilog and source cross-probing to live debugging.
Future<void> main() async {
  SourceTracer.activate();
  try {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final load = Logic(name: 'load');
    final parallelData = Logic(name: 'parallelData', width: 8);
    final dut = Serializer(clk, reset, load, parallelData);
    await dut.build();

    final packageRoot = Directory.current.path;
    final outputDirectory = '$packageRoot/build/serializer_debug';
    NetlistService(
      dut,
      packageRoot: packageRoot,
      outputDirectory: outputDirectory,
    ).writeOutputs();

    final sv = SystemVerilogService(
      dut,
      outputDirectory: outputDirectory,
      multiFile: true,
      embedSourceTraceComments: false,
    )..writeOutputs();
    TraceService(
      dut,
      svService: sv,
      packageRoot: packageRoot,
      svOutputMode: SvOutputMode.perModule,
    ).write(outputDirectory);

    WaveformService(
      dut,
      outputDirectory: outputDirectory,
      outputBaseName: 'serializer',
      writeToFile: true,
      enableDevToolsStreaming: true,
    );

    await simulateSerializer(
      clk: clk,
      reset: reset,
      load: load,
      parallelData: parallelData,
    );
  } finally {
    SourceTracer.clear();
  }
}
