/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// a_logic_width.dart
/// Creation logic value and width in rohd.
///
/// 2023 February 20
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';
import 'helper.dart';

class BasicLogic extends Module {
  late final Logic bus;
  late final Logic bigBus;

  BasicLogic() : super(name: 'BasicLogic') {
    bus = Logic(name: 'threeBitBus', width: 3);
    bigBus = Logic(name: 'bigBus', width: 65);

    // Add ports
    final signal1 = addInput('threeBitBus', bus, width: bus.width);
    final signal2 = addInput('bigBus', bus, width: bus.width);
  }
}

void main() async {
  // Instantiate Module and display system verilog
  final basicLogic = BasicLogic();
  await displaySystemVerilog(basicLogic);

  // Simulation with put()!

  // .put() is one way to simulate a signal on a Logic signal that has been
  // created.
  // We will come back to this in later section.
  basicLogic.bus.put(1);

  // Obtain the value of bus.
  final busVal = basicLogic.bus.value;

  // output: 3'h1.
  print('a) The hexadecimal string value of bus is $busVal.');

  // Obtain the value of bus in Int
  final busValInt = basicLogic.bus.value.toInt();

  // output: 1.
  print('b) The integer value of bus is $busValInt.');

  // If you set your bus width larger than 64 bits.
  // You have to use toBigInt().
  basicLogic.bigBus.put(BigInt.parse('9223372036854775808'));
  final bigBusValBigInt = basicLogic.bigBus.value.toBigInt();

  // output: 9223372036854775808.
  print('c) The big integer of bus is $bigBusValBigInt.');
}
