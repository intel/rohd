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

// TODO(user): (Optional) Change [YourModuleName] to your own module name.
class YourModuleName extends Module {
  // TODO(user): (Optional) super(name: 'ModuleName') can be change to your ModuleName.
  YourModuleName() : super(name: 'ModuleName') {
    // TODO(user): (Required) Paste your Logic initialization here.

    // TODO(user): (Required) Declare your input and output port.
  }
}

void main() async {
  // Instantiate Module and display system verilog.
  // TODO(user): (Optional) Update [YourModuleName] .
  final basicLogic = YourModuleName();
  await displaySystemVerilog(basicLogic);
}
