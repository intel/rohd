/// SPDX-License-Identifier: BSD-3-Clause
/// Copyright (C) 2022-2023 Intel Corporation
///
/// shuffle_test.dart
/// Tests related to shuffled bits
///
/// 2022 December 21
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class Shuffler extends Module {
  final int payloadWidth;
  Shuffler(Logic payloadIn1, Logic payloadIn2)
      : payloadWidth = payloadIn1.width + payloadIn2.width {
    payloadIn1 = addInput('payloadIn1', payloadIn1, width: payloadIn1.width);
    payloadIn2 = addInput('payloadIn2', payloadIn2, width: payloadIn2.width);
    final payloadOut = addOutput('payloadOut', width: payloadWidth);

    final innerPayload1 = Logic(name: 'innerPayload1', width: payloadIn1.width)
      ..gets(Passthrough(payloadIn1).out);
    final innerPayload2 = Logic(name: 'innerPayload2', width: payloadIn2.width)
      ..gets(Passthrough(payloadIn2).out);

    payloadOut <=
        List.generate(
          payloadWidth,
          (index) => index.isEven
              ? innerPayload1[index ~/ 2]
              : innerPayload2[index ~/ 2],
        ).reversed.toList().rswizzle();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('shuffle test', () async {
    final gtm = Shuffler(Logic(width: 8), Logic(width: 8));
    await gtm.build();
    final vectors = [
      Vector({'payloadIn1': 0xff, 'payloadIn2': 0}, {'payloadOut': 0xaaaa}),
    ];
    await SimCompare.checkFunctionalVector(gtm, vectors);
    final simResult = SimCompare.iverilogVector(gtm, vectors);
    expect(simResult, equals(true));
  });
}
