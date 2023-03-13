/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_mod_test.dart
/// Unit tests related to Combinationals and other Modules.
///
/// 2022 September 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class IncrModule extends Module {
  Logic get result => output('result');
  IncrModule(Logic toIncr) {
    toIncr = addInput('toIncr', toIncr, width: toIncr.width);
    addOutput('result', width: toIncr.width);
    result <= toIncr + 1;
  }
}

class ReuseExample extends Module {
  ReuseExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    final inc = IncrModule(intermediate);

    Combinational([
      intermediate < a,
      intermediate < inc.result,
      intermediate < inc.result,
    ]);

    b <= intermediate;
  }
}

class DuplicateExample extends Module {
  DuplicateExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    Combinational([
      intermediate < a,
      intermediate < IncrModule(intermediate).result,
      intermediate < IncrModule(intermediate).result,
    ]);

    b <= intermediate;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('module reuse should apply twice', () async {
    final mod = ReuseExample(Logic(width: 8));
    await mod.build();

    final vectors = [
      Vector({'a': 3}, {'b': 5})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('module duplication should apply twice', () async {
    final mod = DuplicateExample(Logic(width: 8));
    await mod.build();

    final vectors = [
      Vector({'a': 3}, {'b': 5})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
