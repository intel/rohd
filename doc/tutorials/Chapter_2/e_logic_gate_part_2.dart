/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// e_logic_gate_part_2.dart
/// Add assignment and mathematical & operator to create Logic Gate.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

class LogicGate extends Module {
  late final Logic a;
  late final Logic b;
  late final Logic c;

  LogicGate() : super(name: 'LogicGate') {
    // Create input and output signals
    a = Logic(name: 'input_a');
    b = Logic(name: 'input_b');
    c = Logic(name: 'output_c');

    // Add ports
    final signal1 = addInput('input_a', a, width: a.width);
    final signal2 = addInput('input_b', b, width: b.width);
    final signal3 = addOutput('output_c', width: c.width);

    c <= signal1 & signal2;
    signal3 <= c;
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final basicLogic = LogicGate();
  await displaySystemVerilog(basicLogic);
}
