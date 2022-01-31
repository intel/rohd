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
      {this.bitWidth = 4, this.depth = 5, name = 'movingSum'})
      : super(name: name) {
    en = addInput('en', en);
    inputVal = addInput('inputVal', inputVal, width: bitWidth);
    // clk = addInput('clk', clk);
    var clk = SimpleClockGenerator(10).clk;
    List<Logic> _z = List<Logic>.generate(
        depth, (index) => Logic(width: bitWidth, name: 'z$index'));

    var out = addOutput('out', width: bitWidth);

    List<ConditionalAssign> _zList = [_z[0] < inputVal];
    for (int i = 0; i < _z.length; i++) {
      if (i == _z.length - 1) {
        _zList.add(out < _z[i]);
      } else {
        _zList.add(_z[i + 1] < _z[i]);
      }
    }

    Sequential(clk, [
      IfBlock([
        Iff(en, _zList),
        Else([
          out < 0,
        ])
      ])
    ]);
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  test('simple pipeline', () async {
    var dut = DelaySignal(
      Logic(),
      Logic(width: 4),
    );
    await dut.build();

    var signalToWidthMap = {'inputVal': 4, 'out': 4};

    var vectors = [
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
    var simResult = SimCompare.iverilogVector(
      dut.generateSynth(),
      dut.runtimeType.toString(),
      vectors,
      signalToWidthMap: signalToWidthMap,
    );
    expect(simResult, equals(true));
  });
}
