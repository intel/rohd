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

class AssignmentOperator extends Module {
  late final Logic a;
  late final Logic b;
  AssignmentOperator() : super(name: 'Assignment') {
    a = Logic(name: 'signal_a');
    b = Logic(name: 'signal_b');

    // In this case, b is connected to a which means they will have the
    // same value.
    final signal1 = addInput('a', a, width: a.width);
    final signal2 = addOutput('b', width: b.width);

    signal2 <= signal1;
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final assignOperator = AssignmentOperator();
  await displaySystemVerilog(assignOperator);

  assignOperator.a.put(1);

  // we can access the signal by naviagate through the iterable.
  final portB =
      assignOperator.signals.firstWhere((element) => element.name == 'b');
  print('The value of b is ${portB.value}.');
}
