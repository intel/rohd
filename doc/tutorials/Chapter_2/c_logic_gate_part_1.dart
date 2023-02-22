/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// c_logic_gate_part_1.dart
/// Initialize of logic gate Logic.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

void main() async {
  // Create a logic for input and output
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final c = Logic(name: 'c');

  // Instantiate Module and display system verilog
  final basicLogic = Part1LogicGate(a, b, c);
  await displaySystemVerilog(basicLogic);
}
