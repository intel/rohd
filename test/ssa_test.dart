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
          s(x) < a + 1, // x = a + 1
          If(s(x) > 3, // if(a + 1 > 3)
              then: [
                s(x) < s(x) + 2, // x = a + 3
              ],
              orElse: [
                s(x) < s(x) + 3, // x = a + 4
              ]),
          s(x) < s(x) + 1, // x = (a + 1 > 3) ? a + 4 : a + 5
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
          Case(s(x) % 2, conditionalType: ConditionalType.priority, [
            CaseItem(s(x) % 3, [s(x) < s(x) + 4]),
            CaseItem(s(x) % 5, [s(x) < s(x) + 8]),
          ], defaultItem: [
            s(x) < 3
          ]),
          s(x) < s(x) + 2
        ]);
  }
}

//TODO: test with multiple ssa things connected to each other that it doesnt get confused!
//TODO: test crazy hierarcical if/else things
//TODO: test where an SSA conditional is generated during generation of another SSA conditional
//TODO: test that uninitialized variable throws exception
//TODO: test when variable is not "initialized"

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

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
        Vector({'a': a}, {'x': (a + 1 > 3) ? a + 4 : a + 5})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa case', () async {
    final mod = SsaModCase(Logic(width: 8));
    await mod.build();

    int xCalc(int a) {
      var x = a + 1;
      x = x + 1;
      final match = x % 2;
      if (match == x % 3) {
        x = x + 4;
      } else if (match == x % 5) {
        x = x + 8;
      } else {
        x = 3;
      }
      // ignore: join_return_with_assignment
      x = x + 2;
      return x;
    }

    final vectors = [
      for (var a = 0; a < 50; a++) Vector({'a': a}, {'x': xCalc(a)})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}
