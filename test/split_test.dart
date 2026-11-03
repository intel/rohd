// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// split_test.dart
// Tests Logic and LogicValue splitting helpers.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _SplitModule extends Module {
  _SplitModule(Logic data) {
    data = addInput('data', data, width: 8);
    final chunks = data.split([2, 3, 3]);
    addOutput('low', width: 2) <= chunks[0];
    addOutput('middle', width: 3) <= chunks[1];
    addOutput('high', width: 3) <= chunks[2];
  }
}

void main() {
  tearDown(Simulator.reset);

  test('LogicValue split returns LSB-first irregular chunks', () {
    final chunks = LogicValue.ofString('11010110').split([2, 3, 3]);

    expect(
      chunks,
      [
        LogicValue.ofString('10'),
        LogicValue.ofString('101'),
        LogicValue.ofString('110'),
      ],
    );
    expect(LogicValue.ofString('10').split([0, 2]), [
      LogicValue.empty,
      LogicValue.ofString('10'),
    ]);
  });

  test('Logic split returns live LSB-first chunks', () {
    final data = Logic(width: 8)..put(0xd6);
    final chunks = data.split([2, 3, 3]);

    expect(chunks.map((chunk) => chunk.value), [
      LogicValue.ofString('10'),
      LogicValue.ofString('101'),
      LogicValue.ofString('110'),
    ]);
    data.put(0x2d);
    expect(chunks.map((chunk) => chunk.value), [
      LogicValue.ofString('01'),
      LogicValue.ofString('011'),
      LogicValue.ofString('001'),
    ]);
  });

  test('split validates chunk widths', () {
    final logic = Logic(width: 4);
    final value = LogicValue.ofInt(0, 4);

    for (final widths in [
      [1, 2],
      [1, -1, 4],
    ]) {
      expect(() => logic.split(widths), throwsArgumentError);
      expect(() => value.split(widths), throwsArgumentError);
    }
  });

  test('split chunks synthesize and simulate', () async {
    final module = _SplitModule(Logic(width: 8));
    await module.build();
    final vectors = [
      Vector({'data': 0xd6}, {'low': 2, 'middle': 5, 'high': 6}),
      Vector({'data': 0x2d}, {'low': 1, 'middle': 3, 'high': 1}),
    ];

    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });
}
