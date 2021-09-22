/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// example_test.dart
/// Tests to make sure that the examples don't break.
/// 
/// 2021 September 17
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:test/test.dart';

import '../example/counter.dart' as counter;
import '../example/tree.dart' as tree;

void main() {
  test('counter example', () => counter.main(noPrint: true));
  test('tree example', () => tree.main(noPrint: true));
}