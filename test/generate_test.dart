// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// generate_test.dart
// Tests for GenerateIf and GenerateFor constructs.
//
// 2026 June
// Author: Joel Kimmel

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// A simple adder module for use as a generate body.
class SimpleAdder extends Module {
  Logic get sum => output('sum');

  SimpleAdder(Logic a, Logic b, {int width = 8, super.name = 'simple_adder'}) {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('sum', width: width);

    sum <= a + b;
  }
}

/// An adder that also outputs a carry bit.
class WideAdder extends Module {
  Logic get sum => output('sum');

  WideAdder(Logic a, Logic b, {int width = 8, super.name = 'wide_adder'}) {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('sum', width: width);

    // Compute sum with wrapping
    sum <= a + b;
  }
}

/// An adder that masks the result (different implementation path).
class NarrowAdder extends Module {
  Logic get sum => output('sum');

  NarrowAdder(Logic a, Logic b, {int width = 8, super.name = 'narrow_adder'}) {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('sum', width: width);

    sum <= a & b;
  }
}

/// A simple inverter module for use in GenerateFor.
class SimpleInverter extends Module {
  Logic get out => output('out');

  SimpleInverter(Logic inp, {super.name = 'simple_inverter'}) {
    inp = addInput('inp', inp);
    addOutput('out');

    out <= ~inp;
  }
}

/// Top module using GenerateIf with then-only (no else).
class TopWithGenerateIfThenOnly extends Module {
  Logic get result => output('result');

  TopWithGenerateIfThenOnly(Logic a, Logic b,
      {int width = 8, bool condition = true})
      : super(name: 'top_gen_if_then_only') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('result', width: width);

    final genIf = GenerateIf(
      conditionExpression: 'WIDTH > 4',
      conditionValue: condition,
      inputs: {'a': a, 'b': b},
      outputWidths: {'sum': width},
      thenBody: (inputs) =>
          SimpleAdder(inputs['a']!, inputs['b']!, width: width),
    );

    result <= genIf.output('sum');
  }
}

/// Top module using GenerateIf with both then and else branches.
class TopWithGenerateIfElse extends Module {
  Logic get result => output('result');

  TopWithGenerateIfElse(Logic a, Logic b,
      {int width = 8, bool condition = true})
      : super(name: 'top_gen_if_else') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('result', width: width);

    final genIf = GenerateIf(
      conditionExpression: 'WIDTH > 4',
      conditionValue: condition,
      inputs: {'a': a, 'b': b},
      outputWidths: {'sum': width},
      thenBody: (inputs) => WideAdder(inputs['a']!, inputs['b']!, width: width),
      elseBody: (inputs) =>
          NarrowAdder(inputs['a']!, inputs['b']!, width: width),
    );

    result <= genIf.output('sum');
  }
}

/// Top module using GenerateFor with inverters.
class TopWithGenerateFor extends Module {
  Logic get out => output('out');

  final ModuleParameter<int> countParam;

  TopWithGenerateFor(Logic inp, {int count = 4})
      : countParam = ModuleParameter<int>('N', defaultValue: count),
        super(name: 'top_gen_for') {
    addModuleParameter(countParam);

    inp = addInput('inp', inp);
    addOutput('out', width: count, widthExpression: countParam.toExpression());

    final genFor = GenerateFor(
      count: count,
      countExpression: countParam.name,
      inputs: {'inp': inp},
      outputWidths: {'out': 1},
      bodyBuilder: (i, inputs) => SimpleInverter(inputs['inp']!),
    );

    out <= genFor.output('out');
  }
}

/// A module with a deliberately different output name for testing mismatches.
class MismatchedOutputModule extends Module {
  MismatchedOutputModule(Logic a, Logic b, {int width = 8})
      : super(name: 'mismatched') {
    a = addInput('a', a, width: width);
    addInput('b', b, width: width);
    addOutput('different_name', width: width);
    output('different_name') <= a;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('GenerateIf', () {
    test('then-only: simulation uses then branch', () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final mod = TopWithGenerateIfThenOnly(a, b);
      await mod.build();

      a.put(5);
      b.put(3);
      expect(mod.result.value.toInt(), equals(8));
    });

    test('if-else: condition true uses then branch (adder)', () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final mod = TopWithGenerateIfElse(a, b);
      await mod.build();

      a.put(10);
      b.put(6);
      // WideAdder: sum = a + b = 16
      expect(mod.result.value.toInt(), equals(16));
    });

    test('if-else: condition false uses else branch (AND)', () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final mod = TopWithGenerateIfElse(a, b, condition: false);
      await mod.build();

      a.put(0x0F);
      b.put(0x33);
      // NarrowAdder: sum = a & b = 0x03
      expect(mod.result.value.toInt(), equals(0x03));
    });

    test('generates SV with generate if block (then-only)', () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final mod = TopWithGenerateIfThenOnly(a, b);
      await mod.build();

      final sv = mod.generateSynth();
      expect(sv, contains('generate'));
      expect(sv, contains('if (WIDTH > 4) begin : gen_then'));
      expect(sv, contains('endgenerate'));
    });

    test('generates SV with generate if-else block', () async {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final mod = TopWithGenerateIfElse(a, b);
      await mod.build();

      final sv = mod.generateSynth();
      expect(sv, contains('generate'));
      expect(sv, contains('if (WIDTH > 4) begin : gen_then'));
      expect(sv, contains('end else begin : gen_else'));
      expect(sv, contains('endgenerate'));
    });

    test('throws on port name mismatch between branches', () {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);

      expect(
        () => GenerateIf(
          conditionExpression: 'X',
          conditionValue: true,
          inputs: {'a': a, 'b': b},
          outputWidths: {'sum': 8},
          thenBody: (inputs) => SimpleAdder(inputs['a']!, inputs['b']!),
          elseBody: (inputs) =>
              MismatchedOutputModule(inputs['a']!, inputs['b']!),
        ),
        throwsA(isA<IllegalConfigurationException>()),
      );
    });

    test('throws on port width mismatch between branches', () {
      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);

      // When the else branch expects different widths, an error is thrown
      // because the shared internal inputs have the width of the declared
      // inputs (8), but the else branch module expects width 4.
      expect(
        () => GenerateIf(
          conditionExpression: 'X',
          conditionValue: true,
          inputs: {'a': a, 'b': b},
          outputWidths: {'sum': 8},
          thenBody: (inputs) => SimpleAdder(inputs['a']!, inputs['b']!),
          elseBody: (inputs) =>
              SimpleAdder(inputs['a']!, inputs['b']!, width: 4),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('GenerateFor', () {
    test('simulation: all iterations produce correct output', () async {
      final inp = Logic(name: 'inp');
      final mod = TopWithGenerateFor(inp);
      await mod.build();

      inp.put(1);
      for (var i = 0; i < 4; i++) {
        expect(mod.out[i].value.toInt(), equals(0));
      }

      inp.put(0);
      for (var i = 0; i < 4; i++) {
        expect(mod.out[i].value.toInt(), equals(1));
      }
    });

    test('generates SV with generate for block', () async {
      final inp = Logic(name: 'inp');
      final mod = TopWithGenerateFor(inp);
      await mod.build();

      final sv = mod.generateSynth();
      expect(sv, contains('genvar i;'));
      expect(sv, contains('generate'));
      expect(sv, contains('for (i = 0; i < N; i = i + 1)'));
      expect(sv, contains('begin : gen_for_block'));
      expect(sv, contains('endgenerate'));
    });

    test('throws on count < 1', () {
      final inp = Logic(name: 'inp');

      expect(
        () => GenerateFor(
          count: 0,
          countExpression: 'N',
          inputs: {'inp': inp},
          outputWidths: {'out': 1},
          bodyBuilder: (i, inputs) => SimpleInverter(inputs['inp']!),
        ),
        throwsA(isA<IllegalConfigurationException>()),
      );
    });

    test('single iteration works', () async {
      final inp = Logic(name: 'inp');
      final mod = TopWithGenerateFor(inp, count: 1);
      await mod.build();

      inp.put(1);
      expect(mod.out.value.toInt(), equals(0));
    });
  });
}
