/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// conditionals_test.dart
/// Unit tests for conditional calculations (e.g. always_comb, always_ff)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/conditionals/conditional_exceptions.dart';
import 'package:rohd/src/exceptions/sim_compare/sim_compare_exceptions.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ShorthandAssignModule extends Module {
  ShorthandAssignModule(
      Logic preIncr, Logic preDecr, Logic mulAssign, Logic divAssign, Logic b)
      : super(name: 'shorthandmodule') {
    preIncr = addInput('preIncr', preIncr, width: 8);
    preDecr = addInput('preDecr', preDecr, width: 8);
    mulAssign = addInput('mulAssign', mulAssign, width: 8);
    divAssign = addInput('divAssign', divAssign, width: 8);
    b = addInput('b', b, width: 8);

    final piOut = addOutput('piOut', width: 8);
    final pdOut = addOutput('pdOut', width: 8);
    final maOut = addOutput('maOut', width: 8);
    final daOut = addOutput('daOut', width: 8);
    final piOutWithB = addOutput('piOutWithB', width: 8);
    final pdOutWithB = addOutput('pdOutWithB', width: 8);

    Combinational([
      piOutWithB < preIncr,
      pdOutWithB < preDecr,
      piOut < preIncr,
      pdOut < preDecr,
      maOut < mulAssign,
      daOut < divAssign,
      // Add these tests
      piOut.incr(),
      pdOut.decr(),
      piOutWithB.incr(b),
      pdOutWithB.decr(b),
      maOut.mulAssign(b),
      daOut.divAssign(b),
    ]);
  }
}

class LoopyCombModule extends Module {
  Logic get a => input('a');
  Logic get x => output('x');
  LoopyCombModule(Logic a) : super(name: 'loopycombmodule') {
    a = addInput('a', a);
    final x = addOutput('x');

    Combinational([
      x < a,
      x < ~x,
    ]);
  }
}

class CaseModule extends Module {
  CaseModule(Logic a, Logic b) : super(name: 'casemodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');

    Combinational([
      Case(
          [b, a].swizzle(),
          [
            CaseItem(Const(LogicValue.ofString('01')), [c < 1, d < 0]),
            CaseItem(Const(LogicValue.ofString('10')), [
              c < 1,
              d < 0,
            ]),
          ],
          defaultItem: [
            c < 0,
            d < 1,
          ],
          conditionalType: ConditionalType.unique),
      CaseZ(
          [b, a].rswizzle(),
          [
            CaseItem(Const(LogicValue.ofString('1z')), [
              e < 1,
            ])
          ],
          defaultItem: [
            e < 0,
          ],
          conditionalType: ConditionalType.priority)
    ]);
  }
}

class IfBlockModule extends Module {
  IfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      IfBlock([
        Iff(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class SingleIfBlockModule extends Module {
  SingleIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');

    Combinational([
      IfBlock([
        Iff.s(a, c < 1),
      ])
    ]);
  }
}

class ElseIfBlockModule extends Module {
  ElseIfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      IfBlock([
        ElseIf(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class SingleElseIfBlockModule extends Module {
  SingleElseIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      IfBlock([
        ElseIf.s(a, c < 1),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class CombModule extends Module {
  CombModule(Logic a, Logic b, Logic d) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');

    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Combinational([
      If(a, then: [
        y < a,
        z < b,
        x < a & b,
        q < d,
      ], orElse: [
        If(b, then: [
          y < b,
          z < a,
          q < 13,
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SequentialModule extends Module {
  SequentialModule(Logic a, Logic b, Logic d) : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');

    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Sequential(SimpleClockGenerator(10).clk, [
      If(a, then: [
        q < d,
        y < a,
        z < b,
        x < ~x, // invert x when a
      ], orElse: [
        x < a, // reset x to a when not a
        If(b, then: [
          y < b,
          z < a
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SingleIfModule extends Module {
  SingleIfModule(Logic a) : super(name: 'combmodule') {
    a = addInput('a', a);

    final q = addOutput('q');

    Combinational(
      [
        If.s(a, q < 1),
      ],
    );
  }
}

class SingleIfOrElseModule extends Module {
  SingleIfOrElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q');
    final x = addOutput('x');

    Combinational(
      [
        If.s(a, q < 1, x < 1),
      ],
    );
  }
}

class SingleElseModule extends Module {
  SingleElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q');
    final x = addOutput('x');

    Combinational([
      IfBlock([
        Iff.s(a, q < 1),
        Else.s(x < 1),
      ])
    ]);
  }
}

class SignalRedrivenSequentialModule extends Module {
  SignalRedrivenSequentialModule(Logic a, Logic b, Logic d)
      : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final q = addOutput('q', width: d.width);
    d = addInput('d', d, width: d.width);

    final k = addOutput('k', width: 8);
    Sequential(SimpleClockGenerator(10).clk, [
      If(a, then: [
        k < k,
        q < k,
        q < d,
      ])
    ]);
  }
}

class SignalRedrivenSequentialModuleWithX extends Module {
  SignalRedrivenSequentialModuleWithX(Logic a, Logic c, Logic d)
      : super(name: 'redrivenwithvalidinvalidsignal') {
    a = addInput('a', a);
    c = addInput('c', c);
    d = addInput('d', d);

    final b = addOutput('b');

    Sequential(SimpleClockGenerator(10).clk, [
      If(a, then: [b < c]),
      If(d, then: [b < c])
    ]);
  }
}

class MultipleConditionalModule extends Module {
  MultipleConditionalModule(Logic a, Logic b)
      : super(name: 'multiplecondmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');

    final Conditional condOne = c < 1;

    Combinational([
      IfBlock([ElseIf.s(a, condOne), ElseIf.s(b, condOne)])
    ]);

    Combinational([
      IfBlock([ElseIf.s(a, condOne), ElseIf.s(b, condOne)])
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('functional', () {
    test('conditional loopy comb', () async {
      final mod = LoopyCombModule(Logic());
      await mod.build();
      mod.a.put(1);
      expect(mod.x.value.toInt(), equals(0));
    });
  });

  group('simcompare', () {
    test('conditional comb', () async {
      final mod = CombModule(Logic(), Logic(), Logic(width: 10));
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0, 'd': 5},
            {'y': 0, 'z': 1, 'x': LogicValue.x, 'q': LogicValue.x}),
        Vector({'a': 0, 'b': 1, 'd': 6},
            {'y': 1, 'z': 0, 'x': LogicValue.x, 'q': 13}),
        Vector({'a': 1, 'b': 0, 'd': 7}, {'y': 1, 'z': 0, 'x': 0, 'q': 7}),
        Vector({'a': 1, 'b': 1, 'd': 8}, {'y': 1, 'z': 1, 'x': 1, 'q': 8}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('iffblock comb', () async {
      final mod = IfBlockModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('single iffblock comb', () async {
      final mod = SingleIfBlockModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1}, {'c': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('elseifblock comb', () async {
      final mod = ElseIfBlockModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('single elseifblock comb', () async {
      final mod = SingleElseIfBlockModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 1}, {'c': 1}),
        Vector({'a': 0}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('case comb', () async {
      final mod = CaseModule(Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1, 'e': 0}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0, 'e': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0, 'e': 1}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1, 'e': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('conditional ff', () async {
      final mod = SequentialModule(Logic(), Logic(), Logic(width: 8));
      await mod.build();
      final vectors = [
        Vector({'a': 1, 'd': 1}, {}),
        Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 1}),
        Vector({'a': 0, 'b': 1, 'd': 3}, {'y': 0, 'z': 1, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 0, 'd': 4}, {'y': 1, 'z': 0, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 1, 'd': 5}, {'y': 1, 'z': 0, 'x': 1, 'q': 4}),
        Vector({}, {'y': 1, 'z': 1, 'x': 0, 'q': 5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('should return exception if a conditional is used multiple times.',
        () async {
      expect(
          () => MultipleConditionalModule(Logic(), Logic()), throwsException);
    });
  });

  test(
      'should return true on simcompare when '
      'execute if.s() for single if...else conditional without orElse.',
      () async {
    final mod = SingleIfModule(Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return true on simcompare when '
      'execute if.s() for single if...else conditional with orElse.', () async {
    final mod = SingleIfOrElseModule(Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
      Vector({'a': 0}, {'x': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return true on simcompare when '
      'execute Else.s() for single else conditional', () async {
    final mod = SingleElseModule(Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1}, {'q': 1}),
      Vector({'a': 0}, {'x': 1}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test(
      'should return SignalRedrivenException when there are multiple drivers '
      'for a flop.', () async {
    final mod =
        SignalRedrivenSequentialModule(Logic(), Logic(), Logic(width: 8));
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'd': 1}, {}),
      Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 1}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(SignalRedrivenException));
    }
  });

  test(
      'should return NonSupportedTypeException when '
      'simcompare expected output values has invalid runtime type. ', () async {
    final mod = SequentialModule(Logic(), Logic(), Logic(width: 8));
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'd': 1}, {}),
      Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 'invalid runtime type'}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(NonSupportedTypeException));
    }
  });

  test(
      'should return SignalRedrivenException when driven with '
      'x signals and valid signals.', () async {
    final mod = SignalRedrivenSequentialModuleWithX(Logic(), Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': LogicValue.x, 'd': 1, 'c': 1}, {'b': LogicValue.z}),
      Vector({'a': 1, 'd': 1, 'c': 1}, {'b': 1}),
    ];

    try {
      await SimCompare.checkFunctionalVector(mod, vectors);
      fail('Exception not thrown!');
    } on Exception catch (e) {
      expect(e.runtimeType, equals(SignalRedrivenException));
    }
  });

  test('shorthand operations', () async {
    final mod = ShorthandAssignModule(Logic(width: 8), Logic(width: 8),
        Logic(width: 8), Logic(width: 8), Logic(width: 8));
    await mod.build();
    final vectors = [
      Vector({
        'preIncr': 5,
        'preDecr': 5,
        'mulAssign': 5,
        'divAssign': 5,
        'b': 5
      }, {
        'piOutWithB': 10,
        'pdOutWithB': 0,
        'piOut': 6,
        'pdOut': 4,
        'maOut': 25,
        'daOut': 1,
      }),
      Vector({
        'preIncr': 5,
        'preDecr': 5,
        'mulAssign': 5,
        'divAssign': 5,
        'b': 0
      }, {
        'piOutWithB': 5,
        'pdOutWithB': 5,
        'piOut': 6,
        'pdOut': 4,
        'maOut': 0,
        'daOut': LogicValue.x,
      }),
      Vector({
        'preIncr': 0,
        'preDecr': 0,
        'mulAssign': 0,
        'divAssign': 0,
        'b': 5
      }, {
        'piOutWithB': 5,
        'pdOutWithB': 0xfb,
        'piOut': 1,
        'pdOut': 0xff,
        'maOut': 0,
        'daOut': 0,
      })
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
