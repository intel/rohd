/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// sv_module.dart
/// A template to run code in chapter 2 tutorials.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import '../helper.dart';

class YourModuleName extends Module {
  // Adjust the number of the signals in the constructor parameters
  YourModuleName(Logic signal1, Logic signal2) : super(name: 'ModuleName') {
    signal1 = addInput('signal_1', signal1, width: signal1.width);
    signal2 = addInput('signal_2', signal2, width: signal2.width);
  }
}

void main() async {
  // Instantiate Module and display system verilog.
  // TODO: Add error handling for network requests
  final basicLogic = YourModuleName(Logic(), Logic());
  await displaySystemVerilog(basicLogic);
}
