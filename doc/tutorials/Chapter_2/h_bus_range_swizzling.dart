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

class RangeSwizzling extends Module {
  late final Logic a;
  late final Logic b;
  late final Logic c;
  late final Logic d;
  late final Logic e;
  late final Logic f;

  RangeSwizzling() : super(name: 'RangeSwizzling') {
    // Declare Constant
    a = Logic(name: 'signal_a', width: 4);
    b = Logic(name: 'signal_b', width: 8);
    c = Const(7, width: 5);
    d = Logic(name: 'signal_d');
    e = Logic(name: 'signal_e', width: d.width + c.width + a.width);
    f = Logic(name: 'signal_f', width: d.width + c.width + a.width);

    // Add ports
    final signal1 = addOutput('output_d', width: d.width);
    final signal2 = addOutput('output_e', width: e.width);
    final signal3 = addOutput('output_f', width: f.width);

    // assign d to the top bit of a
    // construct e by swizzling bits from b, c, and d
    // here, the MSB is on the left, LSB is on the right
    d <= b[7];
    signal1 <= d;

    // value:
    // swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB) ,
    // e = [1 00111 1110] = [d, c, a]
    e <= [d, c, a].swizzle();
    signal2 <= e;

    // alternatively, do a reverse swizzle
    // (useful for lists where 0-index is actually the 0th element)
    //
    // Here, the LSB is on the left, the MSB is on the right
    // right swizzle: d = [1] (MSB), c = [00111], a = [1110] (LSB),
    // e = [1110 00111 1] - [a, c, d]
    f <= [d, c, a].rswizzle();
    signal3 <= f;
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final rangeSwizzling = RangeSwizzling();
  await displaySystemVerilog(rangeSwizzling);

  print('\n');

  // assign b to the bottom 3 bits of a
  // input = [1, 1, 1, 0], output = 110
  rangeSwizzling.a.put(bin('1110'));
  print('a.slice(2, 0):'
      ' ${rangeSwizzling.a.slice(2, 0).value.toString(includeWidth: false)}');

  rangeSwizzling.b.put(bin('11000100'));
  print('a[7]: ${rangeSwizzling.b[7].value.toString(includeWidth: false)}');
  print('a[0]: ${rangeSwizzling.b[0].value.toString(includeWidth: false)}');
  print('e: ${rangeSwizzling.e.value.toString(includeWidth: false)}');
  print('f: ${rangeSwizzling.f.value.toString(includeWidth: false)}');
}
