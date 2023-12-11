// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// js_test.dart
// Tests for running ROHD when Dart is compiled to JavaScript
//
// 2023 December 8
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('precision adjustment handled', () {
    for (var i = 1; i < 100; i++) {
      expect(
          LogicValue.of('${'1' * i}0'),
          [
            LogicValue.ofBigInt(BigInt.parse('1' * i, radix: 2), i),
            LogicValue.zero
          ].swizzle());
    }
  });
}
