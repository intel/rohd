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

void main() async {
  final a = Const(5, width: 16);
  // Instantiate Module and display system verilog
  final constantLogic = ConstantValue(a);
  await displaySystemVerilog(constantLogic);

  print('\nValue of a is: ');
  print(constantLogic.a.value.toInt());
}
