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

void main() async {
  final bus = Logic(name: 'threeBitBus', width: 3);
  final bigBus = Logic(name: 'bigBus', width: 65);

  // Instantiate Module and display system verilog
  final basicLogic = LogicInitialization(bus, bigBus);
  await displaySystemVerilog(basicLogic);

  // Simulation with put()!

  // .put() is one way to simulate a signal on a Logic signal that has been
  // created.
  // We will come back to this in later section.
  bus.put(1);

  // Obtain the value of bus.
  final busVal = bus.value;

  print('\nNote:');

  // output: 3'h1.
  print('a) The hexadecimal string value of bus is $busVal.');

  // Obtain the value of bus in Int
  final busValInt = bus.value.toInt();

  // output: 1.
  print('b) The integer value of bus is $busValInt.');

  // If you set your bus width larger than 64 bits.
  // You have to use toBigInt().
  bigBus.put(BigInt.parse('9223372036854775808'));
  final bigBusValBigInt = bigBus.value.toBigInt();

  // output: 9223372036854775808.
  print('c) The big integer of bus is $bigBusValBigInt.');
}
