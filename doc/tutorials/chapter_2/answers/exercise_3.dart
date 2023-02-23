/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// exercise_3.dart
/// Answer to exercise 3.
///
/// 2023 February 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';

Future<void> main() async {
  final a = Const(10, width: 4); // 10 in binary is 1010
  final b = Logic(name: 'copy_of_const', width: a.width);

  b <= a;

  print(b.value.toInt());
}
