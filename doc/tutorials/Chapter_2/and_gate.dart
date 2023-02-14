/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// and_gate.dart
/// A simple AND gate construction.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

void main() {
  // Create input and output signals
  final a = Logic(name: 'input_a');
  final b = Logic(name: 'input_b');
  final c = Logic(name: 'output_c');

  // Create an AND logic gate
  // This assign c to the result of a AND b
  c <= a & b;

  // let try with simple a = 1, b = 1
  // a.put(1);
  // b.put(1);
  // print(c.value.toInt());

  // Let build a truth table
  for (var i = 0; i <= 1; i++) {
    for (var j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print('a: $i, b: $j c: ${c.value.toInt()}');
    }
  }
}
