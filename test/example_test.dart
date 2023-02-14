/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// example_test.dart
/// Tests to make sure that the examples don't break.
///
/// 2021 September 17
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/example.dart' as counter;
import '../example/fir_filter.dart' as fir_filter;
import '../example/tree.dart' as tree;

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('counter example', () async {
    await counter.main(noPrint: true);
  });
  test('tree example', () async {
    await tree.main(noPrint: true);
  });
  test('fir filter example', () async {
    await fir_filter.main(noPrint: true);
  });
}
