/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// exercise_2.dart
/// Answer to exercise 2.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unnecessary_this
import 'package:rohd/rohd.dart';
import '../helper.dart';

void gate(Logic a, Logic b, Logic c) {
  // Note: If you're familiar with SV, you may want to read this section,
  // but if it's new to you, feel free to skip ahead.
  // We'll cover the topic more extensively in Chapters 5, 6, and 7,
  // where you'll have the opportunity to gain a deeper understanding.
  const answer = 'xor'; // 'or', 'nor', 'xor'
  switch (answer) {
    case 'or':
      c <= a | b;
      break;
    case 'nor':
      c <= ~(a | b);
      break;
    case 'xor':
      c <= a ^ b;
      break;
  }
}

void main() async {
  // Create a logic for input and output
  final a = Logic(name: 'a');
  final b = Logic(name: 'b');
  final c = Logic(name: 'c');

  // Instantiate Module and display system verilog
  final basicLogic = LogicGate(a, b, c, gate);
  await displaySystemVerilog(basicLogic);

  // Let build a truth table
  print('\nBuild Truth Table: ');
  for (var i = 0; i <= 1; i++) {
    for (var j = 0; j <= 1; j++) {
      a.put(i);
      b.put(j);
      print('a: $i, b: $j c: ${basicLogic.c.value.toInt()}');
    }
  }
}
