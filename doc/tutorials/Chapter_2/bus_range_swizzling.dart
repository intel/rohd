/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus_range_swizzling.dart
/// Demonstrated the use of bus range and swizzling.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

void main() {
  final a = Logic(width: 4);
  final b = Logic(width: 8);
  final c = Const(7, width: 5);
  final d = Logic();

  // assign b to the bottom 3 bits of a
  // input = [1, 1, 1, 0], output = 110
  a.put(bin('1110'));
  print('a.slice(2, 0): ${a.slice(2, 0).value.toString(includeWidth: false)}');

  b.put(bin('11000100'));
  print('a[7]: ${b[7].value.toString(includeWidth: false)}');
  print('a[0]: ${b[0].value.toString(includeWidth: false)}');

  // assign d to the top bit of a
  // construct e by swizzling bits from b, c, and d
  // here, the MSB is on the left, LSB is on the right
  d <= b[7];

  // value:
  // swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB) , e = [1 00111 1110] = [d, c, a]
  final e = Logic(width: d.width + c.width + a.width);
  e <= [d, c, a].swizzle();

  print('e: ${e.value.toString(includeWidth: false)}');

  // alternatively, do a reverse swizzle (useful for lists where 0-index is actually the 0th element)
  // here, the LSB is on the left, the MSB is on the right
  // right swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB) , e = [1110 00111 1] - [a, c, d]
  final f = Logic(width: d.width + c.width + a.width);
  f <= [d, c, a].rswizzle();
  print('f: ${f.value.toString(includeWidth: false)}');
}
