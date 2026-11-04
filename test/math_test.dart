// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// math_test.dart
// Unit tests for math-related operations
//
// 2021 May 21
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

class MathTestModule extends Module {
  final int c;

  MathTestModule(Logic a, Logic b, {this.c = 5})
      : super(name: 'gatetestmodule') {
    if (a.width != b.width) {
      throw Exception('a and b must be same width');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aPowerB = addOutput('a_power_b', width: a.width);
    final aPlusB = addOutput('a_plus_b', width: a.width);
    final aMinusB = addOutput('a_minus_b', width: a.width);
    final aTimesB = addOutput('a_times_b', width: a.width);
    final aDividedByB = addOutput('a_dividedby_b', width: a.width);
    final aModuloB = addOutput('a_modulo_b', width: a.width);
    final aModuloConst = addOutput('a_modulo_const', width: a.width);

    final aPowerConst = addOutput('a_power_const', width: a.width);
    final aPlusConst = addOutput('a_plus_const', width: a.width);
    final aMinusConst = addOutput('a_minus_const', width: a.width);
    final aTimesConst = addOutput('a_times_const', width: a.width);
    final aDividedByConst = addOutput('a_dividedby_const', width: a.width);

    final aSlB = addOutput('a_sl_b', width: a.width);
    final aSrlB = addOutput('a_srl_b', width: a.width);
    final aSraB = addOutput('a_sra_b', width: a.width);

    final aSlConst = addOutput('a_sl_const', width: a.width);
    final aSrlConst = addOutput('a_srl_const', width: a.width);
    final aSraConst = addOutput('a_sra_const', width: a.width);

    aPowerB <= a.pow(b);
    aPlusB <= a + b;
    aMinusB <= a - b;
    aTimesB <= a * b;
    aDividedByB <= a / b;
    aModuloB <= a % b;
    aModuloConst <= a % c;

    aPowerConst <= a.pow(c);
    aPlusConst <= a + c;
    aMinusConst <= a - c;
    aTimesConst <= a * c;
    aDividedByConst <= a / c;

    aSlB <= a << b;
    aSrlB <= a >>> b;
    aSraB <= a >> b;

    aSlConst <= a << c;
    aSrlConst <= a >>> c;
    aSraConst <= a >> c;
  }
}

class AddWithCarryMod extends Module {
  AddWithCarryMod(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: a.width);
    final sum = addOutput('sum', width: a.width);
    final carry = addOutput('carry');

    final adder = Add(a, b);
    sum <= adder.sum;
    carry <= adder.carry;
  }
}

class AddInvertedWithCarryMod extends Module {
  AddInvertedWithCarryMod({int width = 8}) {
    final a = addInput('a', Logic(width: width), width: width);
    final b = addInput('b', Logic(width: width), width: width);
    final adder = Add(~a, b);
    addOutput('sum', width: width) <= adder.sum;
    addOutput('carry') <= adder.carry;
  }
}

class AddModuloWithCarryMod extends Module {
  AddModuloWithCarryMod() {
    final a = addInput('a', Logic(width: 8), width: 8);
    final b = addInput('b', Logic(width: 8), width: 8);
    final adder = Add(a % 3, b);
    addOutput('sum', width: 8) <= adder.sum;
    addOutput('carry') <= adder.carry;
  }
}

class AddEmptyWithCarryMod extends Module {
  AddEmptyWithCarryMod() {
    final adder = Add(Logic(width: 0), Logic(width: 0));
    addOutput('carry') <= adder.carry;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  void checkVerilatorVectors(Module module, List<Vector> vectors) {
    if (!kIsWeb) {
      expect(SimCompare.checkVerilatorVector(module, vectors), isTrue);
    }
  }

  group('add with carry', () {
    test('inverted operand keeps its width for the carry', () async {
      final mod = AddInvertedWithCarryMod();
      await mod.build();
      final vectors = [
        Vector({'a': 0xff, 'b': 1}, {'sum': 1, 'carry': 0}),
        Vector({'a': 0, 'b': 1}, {'sum': 0, 'carry': 1}),
        Vector({'a': 0x80, 'b': 0xff}, {'sum': 0x7e, 'carry': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      checkVerilatorVectors(mod, vectors);
    });

    test('inverted one-bit operands and unknowns', () async {
      final mod = AddInvertedWithCarryMod(width: 1);
      await mod.build();
      final vectors = [
        Vector({'a': 0, 'b': 1}, {'sum': 0, 'carry': 1}),
        Vector({'a': 1, 'b': 1}, {'sum': 1, 'carry': 0}),
        Vector({'a': LogicValue.x, 'b': 0},
            {'sum': LogicValue.x, 'carry': LogicValue.x}),
        Vector({'a': LogicValue.z, 'b': 1},
            {'sum': LogicValue.x, 'carry': LogicValue.x}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      checkVerilatorVectors(mod, vectors.take(2).toList());
    });

    test('modulo operand keeps its width for the carry', () async {
      final mod = AddModuloWithCarryMod();
      await mod.build();
      final vectors = [
        Vector({'a': 255, 'b': 255}, {'sum': 255, 'carry': 0}),
        Vector({'a': 254, 'b': 255}, {'sum': 1, 'carry': 1}),
        Vector({'a': 253, 'b': 255}, {'sum': 0, 'carry': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      checkVerilatorVectors(mod, vectors);
    });

    test('zero-width operands produce zero carry', () async {
      final mod = AddEmptyWithCarryMod();
      await mod.build();
      final vectors = [
        Vector({}, {'carry': 0})
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
      checkVerilatorVectors(mod, vectors);
    });

    test('sv gen', () async {
      final mod = AddWithCarryMod(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      expect(sv, contains("assign {carry, sum} = {1'b0, a} + {1'b0, b}"));
    });

    test('simcompare', () async {
      final mod = AddWithCarryMod(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final vectors = [
        Vector({'a': 0, 'b': 0}, {'sum': 0, 'carry': 0}),
        Vector({'a': 0, 'b': 1}, {'sum': 1, 'carry': 0}),
        Vector({'a': 1, 'b': 0}, {'sum': 1, 'carry': 0}),
        Vector({'a': 0xff, 'b': 1}, {'sum': 0, 'carry': 1}),
        Vector({'a': 0xff, 'b': 0xff}, {'sum': 0xfe, 'carry': 1}),
        Vector({'a': 0xfe, 'b': 0xff}, {'sum': 0xfd, 'carry': 1}),
        Vector({'a': 0xff, 'b': 0xfe}, {'sum': 0xfd, 'carry': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  test('sv expansion handles lint issues', () async {
    final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
    await gtm.build();

    final sv = gtm.dumpSystemVerilog();
    final lines = sv.split('\n');

    // ensure we never lshift by a constant directly
    for (final line in lines) {
      if (RegExp('assign.*a_sl_const.*=').hasMatch(line)) {
        expect(line, contains('shiftAmount'));
      }
    }
  });

  group('simcompare', () {
    Future<void> runMathVectors(List<Vector> vectors) async {
      final gtm = MathTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      SimCompare.checkIverilogVector(gtm, vectors);
    }

    test('power', () async {
      await runMathVectors([
        Vector({'a': 1, 'b': 100}, {'a_power_b': 1}),
        Vector({'a': 1043, 'b': 0}, {'a_power_b': 1}),
        Vector({'a': 3, 'b': 3}, {'a_power_b': 27}),
        Vector({'a': 2, 'b': 1}, {'a_power_b': 2}),
        Vector({'a': 2, 'b': 7}, {'a_power_b': 128}),
        Vector({'a': 2}, {'a_power_const': 32}),
        Vector({'a': 5, 'b': 3}, {'a_power_b': 125}),
        Vector({'a': 7, 'b': 2}, {'a_power_b': 49}),
        Vector({'a': 0, 'b': 0}, {'a_power_b': 1}),
        Vector({'a': 0, 'b': 3}, {'a_power_b': 0}),
      ]);
    });

    test('addition', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
        Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
        Vector({'a': 6}, {'a_plus_const': 11}),
      ]);
    });

    test('subtraction', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_minus_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_minus_b': 1}),
        Vector({'a': 0xff, 'b': 0xff}, {'a_minus_b': 0}),
        Vector({'a': 12, 'b': 5}, {'a_minus_b': 7}),
        Vector({'a': 6}, {'a_minus_const': 1}),
      ]);
    });

    test('multiplication', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_times_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_times_b': 1}),
        Vector({'a': 3, 'b': 4}, {'a_times_b': 12}),
        Vector({'a': 6}, {'a_times_const': 30}),
      ]);
    });

    test('division', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_dividedby_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 5, 'b': 2}, {'a_dividedby_b': 2}),
        Vector({'a': 9, 'b': 3}, {'a_dividedby_b': 3}),
        Vector({'a': 6}, {'a_dividedby_const': 1}),
      ]);
    });

    test('modulo', () async {
      await runMathVectors([
        Vector({'a': 0, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 1, 'b': 0}, {'a_modulo_b': LogicValue.x}),
        Vector({'a': 4, 'b': 2}, {'a_modulo_b': 0}),
        Vector({'a': 5, 'b': 2}, {'a_modulo_b': 1}),
        Vector({'a': 9, 'b': 3}, {'a_modulo_b': 0}),
        Vector({'a': 11}, {'a_modulo_const': 1})
      ]);
    });

    test('shift left', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_sl_b': 0xf}),
        Vector({'a': 0xf, 'b': 2}, {'a_sl_b': 0xf << 2}),
        Vector({'a': 0x2}, {'a_sl_const': 0x2 << 5}),
      ]);
    });

    test('shift right logical', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_srl_b': 0xf}),
        Vector({'a': 0xff, 'b': 2}, {'a_srl_b': 0x3f}),
        Vector({'a': bin('11000000')}, {'a_srl_const': bin('00000110')}),
      ]);
    });

    test('shift right arithmetic', () async {
      await runMathVectors([
        Vector({'a': 0xf, 'b': 0}, {'a_sra_b': 0xf}),
        Vector({'a': 0xfe, 'b': 2}, {'a_sra_b': 0xff}),
        Vector({'a': bin('11000000')}, {'a_sra_const': bin('11111110')}),
      ]);
    });
  });
}
