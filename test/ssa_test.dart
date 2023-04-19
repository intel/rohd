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

  static int model(int a) {
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
}

class SsaChain extends Module {
  SsaChain(Logic a) {
    a = addInput('a', a, width: 8);
    final b = Logic(name: 'b', width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(b) < a + 1,
          b.incr(s: s),
        ]);

    Combinational.ssa((s) => [
          s(x) < b + 1,
          x.incr(s: s),
        ]);
  }
}

class SsaMix extends Module {
  SsaMix(Logic a) {
    a = addInput('a', a, width: 8);
    final b = Logic(name: 'b', width: 8);
    final x = addOutput('x', width: 8);

    Combinational.ssa((s) => [
          s(b) < a + 1,
          b.incr(s: s),
          Case((s(b) % 2)[0], [
            CaseItem(Const(0), [
              If(
                s(b) > 5,
                then: [s(b) < s(b) + 5],
              ),
              If(
                (s(b) % 3).eq(Const(0, width: 8)),
                then: [s(b) < s(b) - 1],
                orElse: [s(b) < s(b) + 2],
              ),
            ]),
            CaseItem(Const(1), [
              CaseZ(s(b), [
                CaseItem(Const(LogicValue.ofString('zzzz1z1z')), [
                  s(b) < s(b) * 2,
                ]),
                CaseItem(Const(LogicValue.ofString('zzzz0z0z')), [
                  s(b) < s(b) + 5,
                ]),
              ], defaultItem: [
                s(b) < s(b) + 1,
              ]),
            ]),
          ]),
        ]);

    Combinational.ssa((s) => [
          s(x) < b + 1,
          If(
            a > 20,
            then: [s(x) < s(x) - 1],
            orElse: [s(x) < s(x) + 1],
          ),
          x.incr(s: s),
        ]);
  }

  static int model(int a) {
    var b = a + 1;
    b++;
    final sbMod2 = b % 2;
    if (sbMod2 == 0) {
      if (b > 5) {
        b += 5;
      }

      if (b % 3 == 0) {
        b -= 1;
      } else {
        b += 2;
      }
    } else if (sbMod2 == 1) {
      final bLv = LogicValue.ofInt(b, 8);
      if (bLv[1] == LogicValue.one && bLv[3] == LogicValue.one) {
        b *= 2;
      } else if (bLv[1] == LogicValue.zero && bLv[3] == LogicValue.zero) {
        b += 5;
      } else {
        b += 1;
      }
    }

    var x = b + 1;
    if (a > 20) {
      x = x - 1;
    } else {
      x = x + 1;
    }
    // ignore: join_return_with_assignment
    x++;

    return x;
  }
}

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

    final vectors = [
      for (var a = 0; a < 50; a++) Vector({'a': a}, {'x': SsaModCase.model(a)})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa chain', () async {
    final mod = SsaChain(Logic(width: 8));
    await mod.build();

    final vectors = [
      for (var a = 0; a < 10; a++) Vector({'a': a}, {'x': a + 4})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa mix', () async {
    final mod = SsaMix(Logic(width: 8));
    await mod.build();

    WaveDumper(mod);

    final vectors = [
      for (var a = 0; a < 50; a++) Vector({'a': a}, {'x': SsaMix.model(a)})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors, enableChecking: true);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}
