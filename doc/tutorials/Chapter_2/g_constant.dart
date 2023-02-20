/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// g_constant.dart
/// Creation of constant Logic in rohd.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

class ConstantLogic extends Module {
  ConstantLogic() : super(name: 'ConstantLogic') {
    // Declare Constant
    final x = Const(5, width: 16);
    print('The value of constant x is: ${x.value.toInt()}');

    // Add ports
    final signal1 = addInput('const_x', x, width: x.width);
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final constantLogic = ConstantLogic();
  await displaySystemVerilog(constantLogic);
}
