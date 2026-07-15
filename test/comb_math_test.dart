// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// comb_math_test.dart
// Unit tests based on UTF8 encoding example in issue 158.
//
// 2022 September 20
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ExampleModule extends Module {
  ExampleModule(Logic codepoint) {
    codepoint = addInput('codepoint', codepoint, width: 21);
    final bytes = addOutput('bytes', width: 32);
    final count = Logic(name: 'count', width: 2);

    Combinational([
      If(codepoint.eq(0x2020), then: [
        count < 2,
        bytes <
            ((codepoint >>> (Const(6, width: 5) * count.zeroExtend(5))) +
                    Const(0xE0, width: 21))
                .slice(7, 0)
                .zeroExtend(32),
        count < count - 2,
      ], orElse: [
        // this is necessary for x's in iverilog (https://github.com/steveicarus/iverilog/issues/776)
        bytes < LogicValue.filled(32, LogicValue.x)
      ]),
    ]);
  }

  Logic get bytes => output('bytes');
}

class ExampleModuleSsa extends Module {
  ExampleModuleSsa(Logic codepoint) {
    codepoint = addInput('codepoint', codepoint, width: 21);
    final bytes = addOutput('bytes', width: 32);
    final count = Logic(name: 'count', width: 2);

    Combinational.ssa((s) => [
          If(codepoint.eq(0x2020), then: [
            s(count) < 2,
            bytes <
                ((codepoint >>> (Const(6, width: 5) * s(count).zeroExtend(5))) +
                        Const(0xE0, width: 21))
                    .slice(7, 0)
                    .zeroExtend(32),
            s(count) < s(count) - 2,
          ], orElse: [
            // this is necessary for x's in iverilog (https://github.com/steveicarus/iverilog/issues/776)
            bytes < LogicValue.filled(32, LogicValue.x)
          ]),
        ]);
  }

  Logic get bytes => output('bytes');
}

class SimplerExample extends Module {
  Logic get b => output('b');
  SimplerExample(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 8);

    Combinational([
      inner < 0xf,
      b < a & inner,
      inner < 0,
    ]);
  }
}

class SimplerExampleSsa extends Module {
  Logic get b => output('b');
  SimplerExampleSsa(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 8, naming: Naming.mergeable);

    Combinational.ssa((s) => [
          s(inner) < 0xf,
          b < a & s(inner),
          s(inner) < 0,
        ]);
  }
}

class StagedExample extends Module {
  Logic get b => output('b');
  StagedExample(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 4);

    Combinational([
      inner < 0xf,
      b < a & inner.zeroExtend(8),
      inner < 0,
    ]);
  }
}

class StagedExampleSsa extends Module {
  Logic get b => output('b');
  StagedExampleSsa(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 4);

    Combinational.ssa((s) => [
          s(inner) < 0xf,
          b < a & s(inner).zeroExtend(8),
          s(inner) < 0,
        ]);
  }
}

class PropExample extends Module {
  Logic get b => output('b');
  PropExample(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 8);
    final inner2 = Logic(name: 'inner2', width: 8);

    inner2 <= inner;

    Combinational([
      inner < 0xf,
      b < a & inner2,
      inner < 0,
    ]);
  }
}

class PropExampleSsa extends Module {
  Logic get b => output('b');
  PropExampleSsa(Logic a) {
    a = addInput('a', a, width: 8);
    addOutput('b', width: 8);

    final inner = Logic(name: 'inner', width: 8);
    final inner2 = Logic(name: 'inner2', width: 8);

    inner2 <= inner;

    Combinational.ssa((s) => [
          s(inner) < 0xf,
          b < a & inner2,
          s(inner) < 0,
        ]);
  }
}

class ReducedExample extends Module {
  ReducedExample(Logic codepoint) {
    codepoint = addInput('codepoint', codepoint, width: 21);
    final bytes = addOutput('bytes', width: 32);
    final count = Logic(name: 'count', width: 2);

    Combinational([
      count < 2,
      bytes < (codepoint >>> count).zeroExtend(32),
    ]);
  }

  Logic get bytes => output('bytes');
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('execute math conditionally', () {
    final codepoints = '†† †† † † q†† †'.runes;

    final vectors = <Vector>[];
    for (final inputCodepoint in codepoints) {
      LogicValue expected;
      if (inputCodepoint == 8224) {
        expected = LogicValue.ofInt(0xe2, 32);
      } else {
        expected = LogicValue.filled(32, LogicValue.x);
      }
      vectors.add(Vector({'codepoint': inputCodepoint}, {'bytes': expected}));
    }

    test('normal', () async {
      try {
        final codepoint = Logic(width: 21);
        final mod = ExampleModule(codepoint);
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('ssa', () async {
      final codepoint = Logic(width: 21);
      final mod = ExampleModuleSsa(codepoint);
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });
  // thank you to @chykon in issue #158 for providing this example!

  test('reduced example', () async {
    final codepoint = Logic(width: 21);
    final mod = ReducedExample(codepoint);
    await mod.build();
    final codepoints = '†'.runes;

    final vectors = <Vector>[];
    for (final inputCodepoint in codepoints) {
      codepoint.put(inputCodepoint);
      vectors.add(Vector({'codepoint': inputCodepoint}, {'bytes': 0x808}));
    }

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('simpler example', () {
    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];

    test('normal', () async {
      try {
        final a = Logic(name: 'a', width: 8);
        final mod = SimplerExample(a);
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('ssa', () async {
      final a = Logic(name: 'a', width: 8);
      final mod = SimplerExampleSsa(a);
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('staged example', () {
    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];

    test('normal', () async {
      try {
        final a = Logic(name: 'a', width: 8);
        final mod = StagedExample(a);
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('ssa', () async {
      final a = Logic(name: 'a', width: 8);
      final mod = StagedExampleSsa(a);
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('propagation example', () {
    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];

    test('normal', () async {
      try {
        final a = Logic(name: 'a', width: 8);
        final mod = PropExample(a);
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('ssa', () async {
      // this one can't be fixed with SSA, make sure it still fails
      try {
        final a = Logic(name: 'a', width: 8);
        final mod = PropExampleSsa(a);
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });
  });
}
