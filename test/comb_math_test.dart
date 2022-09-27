/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_math_test.dart
/// Unit tests based on UTF8 encoding example in issue 158.
///
/// 2022 September 20
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
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

    var inner = Logic(name: 'inner', width: 8);

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

    var inner = Logic(name: 'inner', width: 4);

    Combinational([
      inner < 0xf,
      b < a & inner.zeroExtend(8),
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
  tearDown(() {
    Simulator.reset();
  });

  //TODO: make these tests use simcompare

  // thank you to @chykon in issue #158 for providing this example!
  test('execute math conditionally', () async {
    final codepoint = Logic(width: 21);
    final exampleModule = ExampleModule(codepoint);
    await exampleModule.build();
    final codepoints = '†† †† † † q†† †'.runes;
    for (final inputCodepoint in codepoints) {
      codepoint.put(inputCodepoint);
      if (inputCodepoint == 8224) {
        expect(exampleModule.bytes.value, equals(LogicValue.ofInt(0xe2, 32)));
      } else {
        expect(exampleModule.bytes.value,
            equals(LogicValue.filled(32, LogicValue.x)));
      }
    }
  });

  test('reduced example', () async {
    final codepoint = Logic(width: 21);
    final exampleModule = ReducedExample(codepoint);
    await exampleModule.build();
    final codepoints = '†'.runes;
    for (final inputCodepoint in codepoints) {
      codepoint.put(inputCodepoint);
    }
    expect(exampleModule.bytes.value.isValid, isTrue);
    expect(exampleModule.bytes.value, equals(LogicValue.ofInt(0x808, 32)));
  });

  test('simpler example', () async {
    var a = Logic(name: 'a', width: 8);
    var mod = SimplerExample(a);
    await mod.build();
    a.put(0xff);
    expect(mod.b.value, equals(LogicValue.ofString('00001111')));
  });

  test('staged example', () async {
    var a = Logic(name: 'a', width: 8);
    var mod = StagedExample(a);
    await mod.build();
    a.put(0xff);
    expect(mod.b.value, equals(LogicValue.ofString('00001111')));
  });

  //TODO: another test with some signals in between to test propagation
}
