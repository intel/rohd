/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// d_assignment_operator.dart
/// Demo how to the assignment operator work.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

void assignmentOperator(Logic a, Logic b) {
  b <= a;
}

void main() async {
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');

  // Instantiate Module and display system verilog
  final assignOperator = AssignmentOperator(a, b, assignmentOperator);
  await displaySystemVerilog(assignOperator);

  a.put(1);
  print('The value of b is ${assignOperator.b.value}.');
}
