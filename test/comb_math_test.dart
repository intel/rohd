/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_math_test.dart
/// Unit tests based on UTF8 encoding example in issue 158.
///
/// 2022 September 20
/// Author: Max Korbel <max.korbel@intel.com>
///

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

  // thank you to @chykon in issue #158 for providing this example!
  test('execute math conditionally', () async {
    final codepoint = Logic(width: 21);
    final mod = ExampleModule(codepoint);
    await mod.build();
    final codepoints = '†† †† † † q†† †'.runes;

    final vectors = <Vector>[];
    for (final inputCodepoint in codepoints) {
      codepoint.put(inputCodepoint);
      LogicValue expected;
      if (inputCodepoint == 8224) {
        expected = LogicValue.ofInt(0xe2, 32);
      } else {
        expected = LogicValue.filled(32, LogicValue.x);
      }
      vectors.add(Vector({'codepoint': inputCodepoint}, {'bytes': expected}));
    }

    await SimCompare.checkFunctionalVector(mod, vectors);

    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

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
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('simpler example', () async {
    final a = Logic(name: 'a', width: 8);
    final mod = SimplerExample(a);
    await mod.build();

    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('staged example', () async {
    final a = Logic(name: 'a', width: 8);
    final mod = StagedExample(a);
    await mod.build();

    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('propagation example', () async {
    final a = Logic(name: 'a', width: 8);
    final mod = PropExample(a);
    await mod.build();

    final vectors = [
      Vector({'a': 0xff}, {'b': bin('00001111')})
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
