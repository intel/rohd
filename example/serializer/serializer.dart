// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// serializer.dart
// Clocked serializer and shared stimulus for debugger demonstrations.
//
// 2026 October 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// A parallel-load, least-significant-bit-first serializer.
///
/// On each rising clock edge, synchronous reset clears the shift register,
/// otherwise `load` selects between loading `parallelData` and shifting.
class Serializer extends Module {
  /// The least significant bit of the shift register.
  Logic get serialOut => output('serialOut');

  /// Creates a serializer whose width is determined by [parallelData].
  Serializer(Logic clk, Logic reset, Logic load, Logic parallelData,
      {super.name = 'serializer'}) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    load = addInput('load', load);
    parallelData =
        addInput('parallelData', parallelData, width: parallelData.width);
    addOutput('serialOut');

    final shiftRegister =
        Logic(name: 'shiftRegister', width: parallelData.width);
    serialOut <= shiftRegister[0];

    Sequential(clk, reset: reset, [
      If(load,
          then: [shiftRegister < parallelData],
          orElse: [shiftRegister < (shiftRegister >>> 1)]),
    ]);
  }
}

/// Drives three bytes through the demonstration serializer.
///
/// Inputs change on falling edges so the rising-edge register has settled at
/// each inspection point. Set a breakpoint on `load.inject(0)` to inspect a
/// freshly loaded byte, or inside the inner loop to follow individual bits.
Future<void> simulateSerializer({
  required Logic clk,
  required Logic reset,
  required Logic load,
  required Logic parallelData,
}) async {
  reset.inject(1);
  load.inject(0);
  parallelData.inject(0);

  Simulator.setMaxSimTime(400);
  final simulation = Simulator.run();

  await clk.nextNegedge;
  reset.inject(0);

  for (final byte in [0xa5, 0x3c, 0x81]) {
    parallelData.inject(byte);
    load.inject(1);
    await clk.nextNegedge;
    load.inject(0);

    for (var bit = 0; bit < parallelData.width; bit++) {
      await clk.nextNegedge;
    }
  }

  await Simulator.endSimulation();
  await simulation;
}
