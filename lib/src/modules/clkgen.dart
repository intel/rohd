/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// clkgen.dart
/// A simple clock generator (non-synthesizable)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// A very simple clock generator.  Generates a non-synthesizable SystemVerilog
/// representation.
class SimpleClockGenerator extends Module with CustomSystemVerilog {
  /// The number of time units between repetitions of this clock.
  ///
  /// For example, if the [clockPeriod] is 10, then the frequency is 1/10,
  /// and the time between positive edges of the generated clock is 10.
  final int clockPeriod;

  /// The generated clock.
  Logic get clk => output('clk');

  /// Constructs a very simple clock generator.  Generates a non-synthesizable
  /// SystemVerilog representation.
  ///
  /// Set the frequency via [clockPeriod].
  SimpleClockGenerator(this.clockPeriod, {super.name = 'clkgen'}) {
    addOutput('clk');

    clk.glitch.listen((args) {
      Simulator.registerAction(Simulator.time + clockPeriod ~/ 2, () {
        clk.put(~clk.value);
      });
    });
    clk.put(0);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (inputs.isNotEmpty || outputs.length != 1) {
      throw Exception(
          'SimpleClockGenerator has exactly one output and no inputs,'
          ' but saw inputs $inputs and outputs $outputs.');
    }
    final clk = outputs['clk']!;
    return '''
// $instanceName
initial begin
  $clk = 0;
  forever begin
    #${clockPeriod ~/ 2};
    $clk = ~$clk;
  end
end
''';
  }
}
