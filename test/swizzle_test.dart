// Copyright (C) 2022-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// swizzle_test.dart
// Tests for swizzling values
//
// 2022 January 6
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SwizzlyModule extends Module {
  SwizzlyModule(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width + 3);
    b <= [Const(0), Const(1), a, Const(1)].swizzle();
  }
}

class SwizzlyEmpty extends Module {
  SwizzlyEmpty(Logic a) {
    a = addInput('a', a, width: a.width);
    addOutput('b', width: a.width) <=
        [a, <Logic>[].swizzle()].swizzle() +
            <Logic>[].swizzle().zeroExtend(a.width);
  }
}

class SwizzleVariety extends Module {
  SwizzleVariety(Logic a) {
    a = addInput('a', a, width: a.width);
    final swz = [
      Const(0),
      a,
      Logic(name: 'x', width: 4),
      LogicArray(name: 'y', [3], 2),
      Const(3, width: 5),
      LogicStructure([a, Const(2, width: 3)], name: 'z'),
    ].swizzle();
    final b = addOutput('b', width: swz.width);
    b <= swz;
  }
}

class SingleElementSwizzle extends Module {
  SingleElementSwizzle(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);
    // Force creation of Swizzle module with single element
    b <= Swizzle([a]).out;
  }
}

class AllSingleBitSwizzle extends Module {
  AllSingleBitSwizzle() {
    final bits = List.generate(5, (i) => addInput('bit$i', Logic()));
    final b = addOutput('b', width: bits.length);
    b <= bits.swizzle();
  }
}

class NestedSwizzle extends Module {
  NestedSwizzle(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final inner = [a, b].swizzle();
    final outer = [Const(1), inner, Const(0, width: 2)].swizzle();
    final out = addOutput('out', width: outer.width);
    out <= outer;
  }
}

class InlinedSwizzle extends Module {
  InlinedSwizzle(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final swz = [a, b].swizzle();
    final out = addOutput('out', width: swz.width);
    // Inline swizzle in an expression
    out <= swz & Const(bin('11111111'), width: swz.width);
  }
}

class VariedWidthSwizzle extends Module {
  VariedWidthSwizzle() {
    final a = addInput('a', Logic(width: 1), width: 1);
    final b = addInput('b', Logic(width: 12), width: 12);
    final c = addInput('c', Logic(width: 3), width: 3);
    final d = addInput('d', Logic(width: 100), width: 100);
    final e = addInput('e', Logic(width: 7), width: 7);
    final signals = [a, b, c, d, e];
    final out = addOutput('out',
        width: signals.map((s) => s.width).reduce((a, b) => a + b));
    out <= signals.swizzle();
  }
}

class LargeWidthSwizzle extends Module {
  LargeWidthSwizzle() {
    final smallSig =
        addInput('smallSig', Logic(width: 5), width: 5); // indices 0-4
    final mediumSig =
        addInput('mediumSig', Logic(width: 50), width: 50); // indices 5-54
    final largeSig =
        addInput('largeSig', Logic(width: 500), width: 500); // indices 55-554
    final signals = [smallSig, mediumSig, largeSig];

    final totalWidth = signals.map((s) => s.width).reduce((a, b) => a + b);
    final out = addOutput('out', width: totalWidth);
    out <= signals.swizzle();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('Bit Range Annotations', () {
    test('variety of element widths with aligned bit ranges', () async {
      final mod = SwizzleVariety(Logic(width: 8));
      await mod.build();

      final sv = mod.generateSynth();
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // Check that bit ranges are present and properly formatted
      final lines =
          sv.split('\n').where((line) => line.contains('/*')).toList();
      expect(lines.length, greaterThan(3)); // Multiple annotated lines

      // Verify simulation works with generated SV
      final vectors = [
        Vector({'a': 0x55}, {}),
        Vector({'a': 0xAA}, {}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('single element swizzle has no bit range annotations', () async {
      final mod = SingleElementSwizzle(Logic(width: 8));
      await mod.build();

      final sv = mod.generateSynth();

      // Single element should not have braces or bit range annotations
      // Look for bit range annotations specifically (/* number */)
      final hasRangeAnnotations =
          RegExp(r'/\*\s*\d+(?::\d+)?\s*\*/').hasMatch(sv);
      expect(hasRangeAnnotations, equals(false));
      expect(sv, isNot(contains('{'))); // No concatenation braces

      expect(sv, contains('assign b = a;'));

      // Verify functionality
      final vectors = [
        Vector({'a': 0x42}, {'b': 0x42}),
        Vector({'a': 0xFF}, {'b': 0xFF}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('all single-bit elements with aligned annotations', () async {
      final mod = AllSingleBitSwizzle();
      await mod.build();

      final sv = mod.generateSynth();

      // Should have bit range annotations for single bits
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // All should be single bit indices (no colons)
      final annotationLines =
          sv.split('\n').where((line) => line.contains('/*')).toList();
      for (final line in annotationLines) {
        expect(line, isNot(contains(':')));
      }

      expect(sv, contains('bit1, /* 3 */'));

      // Verify functionality
      final vectors = [
        Vector({'bit0': 1, 'bit1': 0, 'bit2': 1, 'bit3': 0, 'bit4': 1},
            {'b': bin('10101')}),
        Vector({'bit0': 0, 'bit1': 1, 'bit2': 1, 'bit3': 1, 'bit4': 0},
            {'b': bin('01110')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('nested swizzles with proper annotations', () async {
      final mod = NestedSwizzle(Logic(width: 4), Logic(width: 3));
      await mod.build();

      final sv = mod.generateSynth();

      // Should contain annotations for both inner and outer swizzles
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // Verify functionality
      final vectors = [
        Vector({'a': 0xA, 'b': 0x5}, {}),
        Vector({'a': 0x3, 'b': 0x7}, {}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('swizzle inlined in expressions maintains annotations', () async {
      final mod = InlinedSwizzle(Logic(width: 4), Logic(width: 4));
      await mod.build();

      final sv = mod.generateSynth();

      // Should have annotations even when swizzle is part of larger expression
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // Verify functionality
      final vectors = [
        Vector({'a': 0xF, 'b': 0x0}, {'out': 0xF0}),
        Vector({'a': 0x3, 'b': 0xC}, {'out': 0x3C}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('varied width elements have properly aligned annotations', () async {
      final mod = VariedWidthSwizzle();
      await mod.build();

      final sv = mod.generateSynth();

      // Should have aligned bit range annotations
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // Get all annotation lines and check alignment
      final annotationLines = sv
          .split('\n')
          .where((line) => line.contains('/*') && line.contains('*/'))
          .toList();

      expect(annotationLines.length, greaterThan(3));

      // Check that multi-bit ranges use colon notation
      final multibitLines =
          annotationLines.where((line) => line.contains(':')).toList();
      expect(multibitLines.length, greaterThan(0));

      // Check that single-bit ranges don't use colon
      final singlebitLines = annotationLines
          .where((line) => line.contains('/*') && !line.contains(':'))
          .toList();
      expect(singlebitLines.length, greaterThan(0));

      // Verify functionality with a simple test
      final vectors = [
        Vector({'a': 1, 'b': 0x123, 'c': 0x5, 'd': 0x42, 'e': 0x7F}, {}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('alignment with different digit widths', () async {
      // Create a module with indices requiring different digit widths
      final largeModule = LargeWidthSwizzle();
      await largeModule.build();
      final sv = largeModule.generateSynth();

      // Should have properly aligned annotations despite different digit counts
      expect(sv, contains('/*'));
      expect(sv, contains('*/'));

      // Get annotation lines and verify they contain proper ranges
      final annotationLines = sv
          .split('\n')
          .where((line) => line.contains('/*') && line.contains('*/'))
          .toList();

      // Should have 3 annotation lines (one per signal)
      expect(annotationLines.length, equals(3));

      // Verify 3-digit indices are present for the large signal
      expect(sv, contains('554'));
      expect(sv, contains('550'));

      // Verify functionality
      final vectors = [
        Vector({
          'smallSig': 0x1F,
          'mediumSig': BigInt.from(0x123456789ABC),
          'largeSig': 0x42
        }, {
          'out': [
            LogicValue.ofBigInt(BigInt.from(0x1F), 5), // smallSig
            LogicValue.ofBigInt(BigInt.from(0x123456789ABC), 50), // mediumSig
            LogicValue.ofBigInt(BigInt.from(0x42), 500) // largeSig
          ].swizzle()
        }),
      ];
      await SimCompare.checkFunctionalVector(largeModule, vectors);
      final simResult = SimCompare.iverilogVector(largeModule, vectors);
      expect(simResult, equals(true));
    });
  });

  test('annotated elements of swizzle in generated sv', () async {
    final mod = SwizzleVariety(Logic(width: 8));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('''
assign b = {
1'h0, /*    34 */
a, /* 33:26 */
x, /* 25:22 */
({
y[2], /* 5:4 */
y[1], /* 3:2 */
y[0]  /* 1:0 */
}), /* 21:16 */
5'h3, /* 15:11 */
({
3'h2, /* 10:8 */
a  /*  7:0 */
})  /* 10: 0 */
};  // swizzle'''));
  });

  group('LogicValue', () {
    test('simple swizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .swizzle(),
          equals(LogicValue.ofString('10xz')));
    });
    test('simple rswizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .rswizzle(),
          equals(LogicValue.ofString('zx01')));
    });
  });
  group('LogicValue of multi-bit', () {
    test('simple swizzle', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].swizzle(),
          equals(LogicValue.ofString('10xz')));
    });

    test('simple rswizzle', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].rswizzle(),
          equals(LogicValue.ofString('xz10')));
    });

    test('64-bit swizzle', () {
      expect(
          List.generate(
              32,
              (index) => index.isEven
                  ? LogicValue.ofString('10')
                  : LogicValue.ofString('xz')).swizzle(),
          equals(LogicValue.ofString('10xz' * 16)));
    });
    test('>64-bit swizzle single concat', () {
      final str1 = '10xz' * 16;
      final str2 = 'xz10' * 10;
      expect([LogicValue.ofString(str2), LogicValue.ofString(str1)].swizzle(),
          equals(LogicValue.ofString(str2 + str1)));
    });
    test('>64-bit swizzle', () {
      expect(
          List.generate(
              40,
              (index) => index.isEven
                  ? LogicValue.ofString('10')
                  : LogicValue.ofString('xz')).swizzle(),
          equals(LogicValue.ofString('10xz' * 20)));
    });

    group('variety of sizes', () {
      test('smaller', () {
        final bits = ['0', '1', 'x', 'z'];
        final swizzleStrings = List.generate(
            100,
            (index) =>
                bits[index % bits.length] * (index % 17) +
                bits[(index + 1) % bits.length] * (index % 2));
        expect(LogicValue.ofIterable(swizzleStrings.map(LogicValue.ofString)),
            equals(LogicValue.ofString(swizzleStrings.reversed.join())));
      });

      test('larger', () {
        final bits = ['0', '1', 'x', 'z'];
        final swizzleStrings = List.generate(
            1000,
            (index) =>
                bits[index % bits.length] * (index % 71) +
                bits[(index + 1) % bits.length] * (index % 2));
        expect(LogicValue.ofIterable(swizzleStrings.map(LogicValue.ofString)),
            equals(LogicValue.ofString(swizzleStrings.reversed.join())));
      });
    });

    group('filled', () {
      test('simple swizzle', () {
        expect(
            [LogicValue.ofString('1' * 4), LogicValue.ofString('1' * 4)]
                .swizzle(),
            equals(LogicValue.ofString('1' * 8)));
      });
      test('big swizzle', () {
        expect(List.generate(100, (index) => LogicValue.one).swizzle(),
            equals(LogicValue.ofString('1' * 100)));
      });
      test('0-width both swizzle', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('')].swizzle(),
            equals(LogicValue.ofString('')));
      });
      test('0-width lhs swizzle', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('111')].swizzle(),
            equals(LogicValue.ofString('111')));
      });
      test('0-width rhs swizzle', () {
        expect([LogicValue.ofString('111'), LogicValue.ofString('')].swizzle(),
            equals(LogicValue.ofString('111')));
      });
    });

    group('non-filled', () {
      test('0-width both swizzle', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('')].swizzle(),
            equals(LogicValue.ofString('')));
      });
      test('0-width lhs swizzle', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('1zx0')].swizzle(),
            equals(LogicValue.ofString('1zx0')));
      });
      test('0-width rhs swizzle', () {
        expect([LogicValue.ofString('1zx0'), LogicValue.ofString('')].swizzle(),
            equals(LogicValue.ofString('1zx0')));
      });
    });
  });

  group('Logic', () {
    test('simple swizzle', () async {
      final mod = SwizzlyModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0}, {'b': bin('0101')}),
        Vector({'a': 1}, {'b': bin('0111')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('const 0-width swizzle', () async {
      final mod = SwizzlyModule(Const(0, width: 0));
      await mod.build();
      final vectors = [
        Vector({}, {'b': bin('011')}),
        Vector({}, {'b': bin('011')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });
  });

  test('zero-width swizzle', () {
    <Logic>[].swizzle();
  });

  test('zero-width swizzle module', () async {
    final mod = SwizzlyEmpty(Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 0}, {'b': bin('0')}),
      Vector({'a': 1}, {'b': bin('1')}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
