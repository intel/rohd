/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// arithmetic_shift_right_test.dart
/// Tests related to special circumstances around arithmetic right-shift.
///
/// 2023 March 1
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SraUnsignedTestModule extends Module {
  Logic get result => output('result');
  SraUnsignedTestModule(Logic toShift, Logic shiftAmount, Logic maskBit) {
    toShift = addInput('toShift', toShift, width: toShift.width);
    shiftAmount =
        addInput('shiftAmount', shiftAmount, width: shiftAmount.width);
    maskBit = addInput('maskBit', maskBit);

    addOutput('result', width: toShift.width);

    result <= (toShift >> shiftAmount) & maskBit.replicate(toShift.width);
  }
}

void main() {
  test('arithmetic shift right and mask', () async {
    final mod =
        SraUnsignedTestModule(Logic(width: 32), Logic(width: 32), Logic());
    await mod.build();
    final vectors = [
      Vector({'toShift': 0xe0000000, 'shiftAmount': 4, 'maskBit': 1},
          {'result': 0xfe000000}),
      Vector({'toShift': 0x10000000, 'shiftAmount': 4, 'maskBit': 1},
          {'result': 0x01000000}),
      Vector({'toShift': 0xe0000000, 'shiftAmount': 4, 'maskBit': 0},
          {'result': 0}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
