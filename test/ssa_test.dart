// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ssa_test.dart
// Tests for SSA behavior.
//
// 2023 April 18
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/exceptions.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

abstract class SsaTestModule extends Module {
  /// The output of this test module.
  Logic get x => output('x');

  SsaTestModule({super.name});

  /// Calculates the expected output [x] given value [a].
  int model(int a);
}

class SsaModAssignsOnly extends SsaTestModule {
  SsaModAssignsOnly(Logic a) : super(name: 'assigns_only') {
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

  @override
  int model(int a) => 4 * a + 3;
}

class SsaModIf extends SsaTestModule {
  SsaModIf(Logic a) : super(name: 'if') {
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

  @override
  int model(int a) => (a + 1 > 3) ? a + 4 : a + 5;
}

class SsaModCase extends SsaTestModule {
  SsaModCase(Logic a) : super(name: 'case') {
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

  @override
  int model(int a) {
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

class SsaChain extends SsaTestModule {
  SsaChain(Logic a) : super(name: 'chain') {
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

  @override
  int model(int a) => a + 4;
}

class SsaMix extends SsaTestModule {
  SsaMix(Logic a) : super(name: 'mix') {
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

  @override
  int model(int a) {
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

class SsaUninit extends Module {
  SsaUninit(Logic a) : super(name: 'uninit') {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);
    Combinational.ssa((s) => [
          s(x) < s(x) + 1,
        ]);
  }
}

class SsaNested extends SsaTestModule {
  SsaNested(Logic a) : super(name: 'nested') {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);
    Combinational.ssa((s) => [
          s(x) < SsaModAssignsOnly(a).x + 1,
        ]);
  }

  @override
  int model(int a) => SsaModAssignsOnly(Logic(width: 8)).model(a) + 1;
}

class SsaMultiDep extends SsaTestModule {
  SsaMultiDep(Logic a) : super(name: 'multidep') {
    a = addInput('a', a, width: 8);
    final x = addOutput('x', width: 8);
    final y = addOutput('y', width: 8);

    Combinational.ssa((s) {
      final mid = Logic(name: 'mid', width: 8);

      final mid2 = s(mid) + 1;

      return [
        s(mid) < a + 1,
        s(x) < mid2 + 1,
        s(y) < mid2 + 1,
      ];
    });
  }

  @override
  int model(int a) => a + 3;
}

class SsaSequenceOfIfs extends Module {
  SsaSequenceOfIfs(Logic a, Logic reset) : super(name: 'seqofifs') {
    final incr = addInput('a', a, width: 8)[0];
    reset = addInput('reset', reset);
    final decr = Const(0);
    final x = addOutput('x', width: 8);

    final val = Logic(width: 8)..put(0); // this is ok for this test...
    final nextVal = Logic(width: 8);

    final checkVal = Const(3, width: 4).zeroExtend(8);

    Combinational.ssa((s) => [
          s(nextVal) < val,
          If(incr, then: [nextVal.incr(s: s)]),
          If(decr & (s(nextVal) > 0), then: [
            nextVal.decr(s: s),
          ]),
          If(s(nextVal) > checkVal, then: [
            s(nextVal) < checkVal,
          ])
        ]);

    Sequential(SimpleClockGenerator(10).clk, reset: reset, [
      val < nextVal,
    ]);

    x <= (nextVal > 0).zeroExtend(8);
  }
}

class SsaSequenceOfCases extends Module {
  SsaSequenceOfCases(Logic a, Logic reset) : super(name: 'seqofifs') {
    final incr = addInput('a', a, width: 8)[0];
    reset = addInput('reset', reset);
    final decr = Const(0);
    final x = addOutput('x', width: 8);

    final val = Logic(width: 8)..put(0); // this is ok for this test...
    final nextVal = Logic(width: 8);

    final checkVal = Const(3, width: 4).zeroExtend(8);

    Combinational.ssa((s) => [
          s(nextVal) < val,
          Case(Const(1), [
            CaseItem(incr, [
              nextVal.incr(s: s),
            ])
          ]),
          Case(Const(1), [
            CaseItem(decr & (s(nextVal) > 0), [
              nextVal.decr(s: s),
            ])
          ]),
          Case(Const(1), [
            CaseItem(s(nextVal) > checkVal, [
              s(nextVal) < checkVal,
            ])
          ]),
        ]);

    Sequential(SimpleClockGenerator(10).clk, reset: reset, [
      val < nextVal,
    ]);

    x <= (nextVal > 0).zeroExtend(8);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('ssa_test_module', () {
    final aInput = Logic(width: 8, name: 'a');
    final mods = [
      SsaModAssignsOnly(aInput),
      SsaModIf(aInput),
      SsaModCase(aInput),
      SsaChain(aInput),
      SsaMix(aInput),
      SsaNested(aInput),
      SsaMultiDep(aInput),
    ];

    for (final mod in mods) {
      test('ssa ${mod.name}', () async {
        await mod.build();

        final vectors = [
          for (var a = 0; a < 50; a++) Vector({'a': a}, {'x': mod.model(a)})
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });

  test('ssa seq of ifs', () async {
    final mod = SsaSequenceOfIfs(Logic(width: 8), Logic());
    await mod.build();

    final vectors = [
      Vector({'a': 0, 'reset': 1}, {}),
      Vector({'a': 0, 'reset': 0}, {}),
      Vector({'a': 0}, {'x': 0}),
      Vector({'a': 0}, {'x': 0}),
      Vector({'a': 1}, {'x': 1}),
      Vector({'a': 1}, {'x': 1}),
      Vector({'a': 1}, {'x': 1}),
    ];

    // make sure we don't have any inferred latches (X's)
    Simulator.registerAction(15, () {
      for (final signal in mod.signals) {
        expect(signal.value.isValid, isTrue);
      }
      for (final signal in mod.signals) {
        signal.changed.listen((event) {
          expect(event.newValue.isValid, isTrue);
        });
      }
    });

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa seq of cases', () async {
    final mod = SsaSequenceOfCases(Logic(width: 8), Logic());
    await mod.build();

    final vectors = [
      Vector({'a': 0, 'reset': 1}, {}),
      Vector({'a': 0, 'reset': 0}, {}),
      Vector({'a': 0}, {'x': 0}),
      Vector({'a': 0}, {'x': 0}),
      Vector({'a': 1}, {'x': 1}),
      Vector({'a': 1}, {'x': 1}),
      Vector({'a': 1}, {'x': 1}),
    ];

    // make sure we don't have any inferred latches (X's)
    Simulator.registerAction(15, () {
      for (final signal in mod.signals) {
        expect(signal.value.isValid, isTrue);
      }
      for (final signal in mod.signals) {
        signal.changed.listen((event) {
          expect(event.newValue.isValid, isTrue);
        });
      }
    });

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('ssa uninitialized', () async {
    expect(() => SsaUninit(Logic(width: 8)),
        throwsA(isA<UninitializedSignalException>()));
  });
}
