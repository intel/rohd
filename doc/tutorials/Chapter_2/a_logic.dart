/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// a_logic.dart
/// Creation of logic in rohd.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, omit_local_variable_types

import 'package:rohd/rohd.dart';
import 'helper.dart';

void main() async {
  // Create a logic
  final Logic unnamedSignal = Logic();

  print(unnamedSignal);

  // 8-bit bus named 'b'.
  final Logic bus = Logic(name: 'b', width: 8);

  // Instantiate Module and display system verilog
  final basicLogic = LogicInitialization(unnamedSignal, bus);
  await displaySystemVerilog(basicLogic);
}
