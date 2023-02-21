/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// a_logic.dart
/// Creation of logic in rohd.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

class BasicLogic extends Module {
  BasicLogic() : super(name: 'BasicLogic') {
    // 1-bit unnamed signal.
    final unamedSignal = Logic();

    // 8-bit bus named 'b'.
    final bus = Logic(name: 'b', width: 8);

    // You can use .toString() method to check for your signals details.
    // Dart will assume you are using.toString() as default if not specify.
    print(unamedSignal);

    // Add ports
    final signal1 = addInput('', unamedSignal);
    final signal2 = addInput('b', bus, width: bus.width);
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final basicLogic = BasicLogic();
  await displaySystemVerilog(basicLogic);
}
