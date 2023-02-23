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
}
