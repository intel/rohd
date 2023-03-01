/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// exercise_1.dart
/// Answer to exercise 1.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print, unused_local_variable

import 'package:rohd/rohd.dart';

Future<void> main() async {
  final threeBitBus = Logic(name: 'threeBitBus');
  print('answer 1: $threeBitBus');

  // that you have created the correct signal?
  print('answer 2: Yes, threeBitBus Logic property output '
      'the name as threeBitBus. Check threeBitBus.name to see a more simple '
      'answer');
}
