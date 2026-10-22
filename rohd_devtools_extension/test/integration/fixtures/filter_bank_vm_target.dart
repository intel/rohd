// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';

import '../../../../example/filter_bank/filter_bank_modules.dart';

Future<void> main() async {
  SourceTracer.activate();
  const dataWidth = 16;
  const numTaps = 3;
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samples = List.generate(
    2,
    (channel) => FilterSample(name: 'sample$channel'),
  );
  final inputDone = Logic(name: 'inputDone');
  final dut = FilterBank(
    clk,
    reset,
    start,
    samples,
    inputDone,
    numTaps: numTaps,
    dataWidth: dataWidth,
    coefficients: const [
      [1, 2, 1],
      [1, -2, 1],
    ],
  );

  await dut.build();
  NetlistService(dut);
  TraceService(dut, packageRoot: Directory.current.path);
  WaveformService(dut, enableDevToolsStreaming: true);

  stdout.writeln('ROHD_VM_TARGET_READY');
  unawaited(
    _runSimulation(
      clk: clk,
      reset: reset,
      start: start,
      samples: samples,
      inputDone: inputDone,
    ),
  );
  final keepAlive = Timer.periodic(const Duration(days: 1), (_) {});
  try {
    await Completer<void>().future;
  } finally {
    keepAlive.cancel();
  }
}

Future<void> _runSimulation({
  required Logic clk,
  required Logic reset,
  required Logic start,
  required List<FilterSample> samples,
  required Logic inputDone,
}) async {
  Simulator.setMaxSimTime(100);
  unawaited(Simulator.run());
  reset.inject(1);
  start.inject(0);
  inputDone.inject(0);
  for (final sample in samples) {
    sample
      ..data.inject(0)
      ..valid.inject(0);
  }

  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);
  start.inject(1);
  await clk.nextPosedge;
  start.inject(0);
  for (final sample in samples) {
    sample
      ..data.inject(1)
      ..valid.inject(1);
  }
  await clk.nextPosedge;
}
