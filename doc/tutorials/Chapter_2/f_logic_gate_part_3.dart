/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// f_logic_gate_part_3.dart
/// Test and simulate the logic gate created using put().
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

void andGate(Logic a, Logic b, Logic c) {
  c <= a & b;
}

void main() async {
  // Create a logic for input and output
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final c = Logic(name: 'c');

  // Instantiate Module and display system verilog
  final basicLogic = LogicGate(a, b, c, andGate);
  await displaySystemVerilog(basicLogic);

  // Let build a truth table
  print('\nBuild Truth Table: ');
  for (var i = 0; i <= 1; i++) {
    for (var j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print('a: $i, b: $j c: ${basicLogic.c.value.toInt()}');
    }
  }
}
