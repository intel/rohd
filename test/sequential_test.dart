/// SPDX-License-Identifier: BSD-3-Clause
/// Copyright (C) 2021-2022 Intel Corporation
///
/// sequential_test.dart
/// Unit test for Sequential
///
/// 2022 January 31
/// Substantial portion of test contributed by wswongat in https://github.com/intel/rohd/issues/79
/// Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class DelaySignal extends Module {
  Logic get out => output('out');

  final int bitWidth;
  final int depth;

  DelaySignal(Logic en, Logic inputVal,
      {this.bitWidth = 4, this.depth = 5, super.name = 'movingSum'}) {
    en = addInput('en', en);
    inputVal = addInput('inputVal', inputVal, width: bitWidth);
    final clk = SimpleClockGenerator(10).clk;
    final z = List<Logic>.generate(
        depth, (index) => Logic(width: bitWidth, name: 'z$index'));

    final out = addOutput('out', width: bitWidth);

    final zList = <ConditionalAssign>[z[0] < inputVal];
    for (var i = 0; i < z.length; i++) {
      if (i == z.length - 1) {
        zList.add(out < z[i]);
      } else {
        zList.add(z[i + 1] < z[i]);
      }
    }

    Sequential(clk, [
      IfBlock([
        Iff(en, zList),
        Else([
          out < 0,
        ])
      ])
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple pipeline', () async {
    final dut = DelaySignal(
      Logic(),
      Logic(width: 4),
    );
    await dut.build();

    final vectors = [
      Vector({'inputVal': 0, 'en': 1}, {}),
      Vector({'inputVal': 1, 'en': 0}, {}),
      Vector({'inputVal': 2, 'en': 0}, {}),
      Vector({'inputVal': 3, 'en': 1}, {}),
      Vector({'inputVal': 4, 'en': 1}, {}),
      Vector({'inputVal': 5, 'en': 1}, {}),
      Vector({'inputVal': 6, 'en': 1}, {}),
      Vector({'inputVal': 7, 'en': 1}, {}),
      Vector({'inputVal': 8, 'en': 1}, {'out': 0}),
      Vector({'inputVal': 9, 'en': 1}, {'out': 3}),
      Vector({}, {'out': 4}),
      Vector({}, {'out': 5}),
    ];
    await SimCompare.checkFunctionalVector(dut, vectors);
    final simResult = SimCompare.iverilogVector(dut, vectors);
    expect(simResult, equals(true));
  });
}
