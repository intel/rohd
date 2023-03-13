/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// vcd_parser_test.dart
/// Tests for the VcdParser
///
/// 2023 February 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/vcd_parser.dart';
import 'package:test/test.dart';

void main() {
  test('VCD parser can parse Icarus Verilog generated VCD file', () {
    final vcdContents =
        File('test/example_icarus_waves.vcd').readAsStringSync();
    for (var countI = 1; countI < 10; countI++) {
      expect(
        VcdParser.confirmValue(
          vcdContents,
          'sampled',
          (10 * countI + 5) * 1000,
          LogicValue.ofInt(countI.isEven ? countI - 2 : countI - 1, 8),
        ),
        isTrue,
      );
    }
  });
}
