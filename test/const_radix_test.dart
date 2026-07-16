// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// const_radix_test.dart
// Tests for preferred radix formatting of constants.
//
// 2026 July 14
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// Exposes constants in each supported radix through generated outputs.
class _ConstRadixModule extends Module {
  _ConstRadixModule() : super(name: 'constRadix') {
    addOutput('autoHex', width: 8) <= Const(42, width: 8);
    addOutput('binaryValue', width: 8) <=
        Const(42, width: 8, preferredRadix: 2);
    addOutput('octalValue', width: 8) <= Const(42, width: 8, preferredRadix: 8);
    addOutput('decimalValue', width: 8) <=
        Const(42, width: 8, preferredRadix: 10);
    addOutput('hexValue', width: 8) <= Const(42, width: 8, preferredRadix: 16);
    addOutput('invalidValue', width: 4) <=
        Const(
          LogicValue.ofString('10xz'),
          preferredRadix: 16,
        );
  }
}

/// Requires its input connection to be a signal rather than an expression.
class _ExpressionlessRadixSub extends Module with SystemVerilog {
  @override
  List<String> get expressionlessInputs => const ['in'];

  _ExpressionlessRadixSub(Logic input) : super(name: 'expressionlessRadix') {
    input = addInput('in', input, width: input.width);
    addOutput('out', width: input.width) <= input;
  }
}

/// Drives an expressionless submodule input with a radix-preferred constant.
class _ExpressionlessRadixTop extends Module {
  _ExpressionlessRadixTop() : super(name: 'expressionlessRadixTop') {
    final sub = _ExpressionlessRadixSub(
      Const(42, width: 8, preferredRadix: 10),
    );
    addOutput('out', width: 8) <= sub.output('out');
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('Const preferred radix', () {
    test('normalizes names using the displayed radix', () {
      expect(Const(42, width: 8).name, 'const_42');
      expect(
        Const(42, width: 8, preferredRadix: 2).name,
        'const_0b101010',
      );
      expect(
        Const(42, width: 8, preferredRadix: 8).name,
        'const_0o52',
      );
      expect(
        Const(42, width: 8, preferredRadix: 10).name,
        'const_42',
      );
      expect(
        Const(42, width: 8, preferredRadix: 16).name,
        'const_0x2a',
      );
    });

    test('derives names from the normalized stored value', () {
      expect(
        Const(-1, width: 8, preferredRadix: 16).name,
        'const_0xff',
      );
      expect(
        Const(BigInt.from(42), width: 8, preferredRadix: 8).name,
        'const_0o52',
      );
      expect(
        Const(
          LogicValue.ofInt(42, 8),
          preferredRadix: 10,
        ).name,
        'const_42',
      );
      expect(
        Const(1, width: 8, fill: true, preferredRadix: 16).name,
        'const_0xff',
      );
      expect(
        Const(
          LogicValue.ofString('10xz'),
          preferredRadix: 16,
        ).name,
        'const_0b10xz',
      );
    });

    test('rejects unsupported radices', () {
      for (final radix in [3, 4, 12]) {
        expect(
          () => Const(1, preferredRadix: radix),
          throwsA(isA<LogicValueConversionException>()),
        );
      }
    });

    test('clone preserves the preference and normalized name', () {
      final original = Const(42, width: 8, preferredRadix: 2);
      final clone = original.clone();

      expect(clone.preferredRadix, 2);
      expect(clone.name, original.name);
      expect(clone.value, original.value);
    });

    test('toString remains a Logic diagnostic', () {
      expect(
        Const(42, width: 8, preferredRadix: 10).toString(),
        'Logic(8): const_42',
      );
    });

    test('normalized names compose into expression names', () {
      final result =
          Logic(name: 'a', width: 8) + Const(42, width: 8, preferredRadix: 16);

      expect(result.name, contains('const_0x2a'));
    });

    test('controls generated SystemVerilog literals', () async {
      final module = _ConstRadixModule();
      await module.build();

      final systemVerilog = module.generateSynth();

      expect(systemVerilog, contains("assign autoHex = 8'h2a;"));
      expect(systemVerilog, contains("assign binaryValue = 8'b101010;"));
      expect(systemVerilog, contains("assign octalValue = 8'o52;"));
      expect(systemVerilog, contains("assign decimalValue = 8'd42;"));
      expect(systemVerilog, contains("assign hexValue = 8'h2a;"));
      expect(systemVerilog, contains("assign invalidValue = 4'b10xz;"));
    });

    test('preserves the preference for expressionless inputs', () async {
      final module = _ExpressionlessRadixTop();
      await module.build();

      final systemVerilog = module.generateSynth();

      expect(systemVerilog, contains("assign in = 8'd42;"));
      expect(systemVerilog, contains('.in(in)'));
      expect(systemVerilog, isNot(contains(".in(8'd42)")));
    });
  });
}
