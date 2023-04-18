// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ssa_test.dart
// Tests for SSA behavior.
//
// 2023 April 18
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SsaModAssignsOnly extends Module {
  Logic get x => output('x');

  SsaModAssignsOnly(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);
    final b = Logic(name: 'b', width: 8);
    Combinational.ssa((s) => [
          s(x) < a, // x = a
          s(b) < s(x) + 1 + s(x), // b = 2a + 1
          s(x) < s(x) + 1, // x = a + 1
          s(x) < s(x) + s(x) + s(b), // x = 2(a + 1) + (2a + 1) = 4a + 3
        ]);
  }
}

class SsaModIf extends Module {
  SsaModIf(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(x) < a + 1,
          If(s(x) > 3, then: [
            s(x) < s(x) + 2,
          ], orElse: [
            s(x) < s(x) + 3,
          ]),
          s(x) < s(x) + 1,
        ]);
  }
}

class SsaModCase extends Module {
  SsaModCase(Logic a) {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(x) < a + 1,
          s(x) < s(x) + 1,
          Case(s(x), [
            CaseItem(s(x), [s(x) < s(x) + 4])
          ], defaultItem: [
            s(x) < 3
          ]),
        ]);
  }
}

//TODO: test with multiple ssa things connected to each other that it doesnt get confused!
//TODO: test crazy hierarcical if/else things
//TODO: test where an SSA conditional is generated during generation of another SSA conditional
//TODO: test that uninitialized variable throws exception
//TODO: test when variable is not "initialized"

void main() {
  test('ssa simple assignments only', () async {
    final a = Logic(width: 8, name: 'a');
    final mod = SsaModAssignsOnly(a);
    await mod.build();

    final vectors = [
      for (var a = 0; a < 10; a++) Vector({'a': a}, {'x': 4 * a + 3})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa if', () async {
    final mod = SsaModIf(Logic(width: 8));
    await mod.build();

    final vectors = [
      for (var a = 0; a < 10; a++)
        Vector({'a': a}, {'x': a < 3 ? a + 5 : a + 4})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa case', () async {
    final mod = SsaModCase(Logic(width: 8));
    await mod.build();
    // print(mod.generateSynth());
  });
}
