/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// basic_logic.dart
/// Creation of logic, logic value and width in rohd.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import 'helper.dart';

class BasicLogic extends Module {
  BasicLogic(Logic unamedSignal, Logic busSignal) : super(name: 'BasicLogic') {
    unamedSignal =
        addInput('unamed_signal', unamedSignal, width: unamedSignal.width);
    busSignal = addInput('busSignal', busSignal, width: busSignal.width);
  }
}

void main() async {
  // 1-bit unnamed signal.
  Logic unamedSignal = Logic();

  // 8-bit bus named 'b'.
  Logic bus = Logic(name: 'b', width: 8);

  // You can use toString() method to check for your signals details.
  print(unamedSignal.toString());

  // Instantiate Module and display system verilog
  final basicLogic = BasicLogic(unamedSignal, bus);
  await displaySystemVerilog(basicLogic);
}
