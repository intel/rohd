// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bus_range_concatenation.dart
// Demonstrates the use of bus range and concatenation.
//
// 2023 February 14
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

// ignore_for_file: avoid_print - tutorial

import 'package:rohd/rohd.dart';
import 'helper.dart';

void slicing(Logic a, Logic b, Logic c, Logic d, Logic e, Logic f, Logic g) {
  // assign d to the top bit of a
  // construct e by concatenation bits from b, c, and d
  // here, the MSB is on the left, LSB is on the right
  d <= b[7];

  // value:
  // concat: d = [1] (MSB), c = [00111], a = [1110] (LSB) ,
  // e = [1 00111 1110] = [d, c, a]
  e <= [d, c, a].concat();

  // alternatively, do a reverse concat
  // (useful for lists where 0-index is actually the 0th element)
  //
  // Here, the LSB is on the left, the MSB is on the right
  // right concat: d = [1] (MSB), c = [00111], a = [1110] (LSB),
  // e = [1110 00111 1] - [a, c, d]
  f <= [d, c, a].rconcat();

  // Get a copy of f with one bit set to 0
  g <= f.withSet(2, Const(0));
}

void main() async {
  // Declare Logic
  final a = Logic(name: 'a', width: 4);
  final b = Logic(name: 'b', width: 8);
  final c = Const(7, width: 5);
  final d = Logic(name: 'd');
  final e = Logic(name: 'e', width: d.width + c.width + a.width);
  final f = Logic(name: 'f', width: d.width + c.width + a.width);
  final g = Logic(name: 'g', width: d.width + c.width + a.width);

  // Instantiate Module and display system verilog
  final rangeConcatenation = RangeConcatenation(a, b, c, d, e, f, g, slicing);
  await displaySystemVerilog(rangeConcatenation);

  print('\n');

  // assign b to the bottom 3 bits of a
  // input = [1, 1, 1, 0], output = 110
  a.put(bin('1110'));
  print('a.slice(2, 0):'
      ' ${a.slice(2, 0).value.toString(includeWidth: false)}');

  b.put(bin('11000100'));
  print('b[7]: ${b[7].value.toString(includeWidth: false)}');
  print('b[0]: ${b[0].value.toString(includeWidth: false)}');

  print('d: ${rangeConcatenation.d.value.toString(includeWidth: false)}');
  print('e: ${rangeConcatenation.e.value.toString(includeWidth: false)}');
  print('f: ${rangeConcatenation.f.value.toString(includeWidth: false)}');
  print('g: ${rangeConcatenation.g.value.toString(includeWidth: false)}');
}
