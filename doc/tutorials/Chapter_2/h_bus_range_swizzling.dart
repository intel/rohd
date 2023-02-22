/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus_range_swizzling.dart
/// Demonstrated the use of bus range and swizzling.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

void slicing(Logic a, Logic b, Logic c, Logic d, Logic e, Logic f) {
  // assign d to the top bit of a
  // construct e by swizzling bits from b, c, and d
  // here, the MSB is on the left, LSB is on the right
  d <= b[7];

  // value:
  // swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB) ,
  // e = [1 00111 1110] = [d, c, a]
  e <= [d, c, a].swizzle();

  // alternatively, do a reverse swizzle
  // (useful for lists where 0-index is actually the 0th element)
  //
  // Here, the LSB is on the left, the MSB is on the right
  // right swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB),
  // e = [1110 00111 1] - [a, c, d]
  f <= [d, c, a].rswizzle();
}

void main() async {
  // Declare Logic
  final a = Logic(name: 'a', width: 4);
  final b = Logic(name: 'b', width: 8);
  final c = Const(7, width: 5);
  final d = Logic(name: 'd');
  final e = Logic(name: 'e', width: d.width + c.width + a.width);
  final f = Logic(name: 'f', width: d.width + c.width + a.width);

  // Instantiate Module and display system verilog
  final rangeSwizzling = RangeSwizzling(a, b, c, d, e, f, slicing);
  await displaySystemVerilog(rangeSwizzling);

  print('\n');

  // assign b to the bottom 3 bits of a
  // input = [1, 1, 1, 0], output = 110
  a.put(bin('1110'));
  print('a.slice(2, 0):'
      ' ${a.slice(2, 0).value.toString(includeWidth: false)}');

  b.put(bin('11000100'));
  print('a[7]: ${b[7].value.toString(includeWidth: false)}');
  print('a[0]: ${b[0].value.toString(includeWidth: false)}');

  print('d: ${rangeSwizzling.d.value.toString(includeWidth: false)}');
  print('e: ${rangeSwizzling.e.value.toString(includeWidth: false)}');
  print('f: ${rangeSwizzling.f.value.toString(includeWidth: false)}');
}
