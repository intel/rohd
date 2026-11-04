// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// concat_test.dart
// Tests for list concatenation values.
//
// 2026 November 4
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:rohd/src/utilities/sv_cleaner.dart';
import 'package:test/test.dart';

class ConcatModule extends Module {
  ConcatModule(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width + 3);
    b <= [Const(0), Const(1), a, Const(1)].concat();
  }
}

class ConcatEmpty extends Module {
  ConcatEmpty(Logic a) {
    a = addInput('a', a, width: a.width);
    addOutput('b', width: a.width) <=
        [a, <Logic>[].concat()].concat() +
            <Logic>[].concat().zeroExtend(a.width);
  }
}

class ConcatVariety extends Module {
  ConcatVariety(Logic a) {
    a = addInput('a', a, width: a.width);
    final swz = [
      Const(0),
      a,
      Logic(name: 'x', width: 4),
      LogicArray(name: 'y', [3], 2),
      Const(3, width: 5),
      LogicStructure([a, Const(2, width: 3)], name: 'z'),
    ].concat();
    final b = addOutput('b', width: swz.width);
    b <= swz;
  }
}

class SingleElementConcat extends Module {
  SingleElementConcat(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);
    // Force creation of Concat module with single element
    b <= Concat([a]).out;
  }
}

class AllSingleBitConcat extends Module {
  AllSingleBitConcat() {
    final bits = List.generate(5, (i) => addInput('bit$i', Logic()));
    final b = addOutput('b', width: bits.length);
    b <= bits.concat();
  }
}

class NestedConcat extends Module {
  NestedConcat(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final inner = [a, b].concat();
    final outer = [Const(1), inner, Const(0, width: 2)].concat();
    final out = addOutput('out', width: outer.width);
    out <= outer;
  }
}

class InlinedConcat extends Module {
  InlinedConcat(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final swz = [a, b].concat();
    final out = addOutput('out', width: swz.width);
    // Inline concat in an expression
    out <= swz & Const(bin('11111111'), width: swz.width);
  }
}

class VariedWidthConcat extends Module {
  VariedWidthConcat() {
    final a = addInput('a', Logic());
    final b = addInput('b', Logic(width: 12), width: 12);
    final c = addInput('c', Logic(width: 3), width: 3);
    final d = addInput('d', Logic(width: 100), width: 100);
    final e = addInput('e', Logic(width: 7), width: 7);
    final signals = [a, b, c, d, e];
    final out = addOutput('out',
        width: signals.map((s) => s.width).reduce((a, b) => a + b));
    out <= signals.concat();
  }
}

class LargeWidthConcat extends Module {
  LargeWidthConcat() {
    final smallSig =
        addInput('smallSig', Logic(width: 5), width: 5); // indices 0-4
    final mediumSig =
        addInput('mediumSig', Logic(width: 50), width: 50); // indices 5-54
    final largeSig =
        addInput('largeSig', Logic(width: 500), width: 500); // indices 55-554
    final signals = [smallSig, mediumSig, largeSig];

    final totalWidth = signals.map((s) => s.width).reduce((a, b) => a + b);
    final out = addOutput('out', width: totalWidth);
    out <= signals.concat();
  }
}

class ConcatAdjacentBitSlices extends Module {
  ConcatAdjacentBitSlices() {
    final a = addInput('a', Logic(width: 8), width: 8);
    addOutput('out', width: 6) <= [a[7], a[6], a[5], a[2], a[1], a[0]].concat();
  }
}

class ConcatAllAdjacentBitSlices extends Module {
  ConcatAllAdjacentBitSlices() {
    final a = addInput('a', Logic(width: 8), width: 8);
    addOutput('out', width: 3) <= [a[7], a[6], a[5]].concat();
  }
}

class ConcatAscendingBitSlices extends Module {
  ConcatAscendingBitSlices() {
    final a = addInput('a', Logic(width: 8), width: 8);
    addOutput('out', width: 3) <= [a[0], a[1], a[2]].concat();
  }
}

class ConcatNestedAdjacentBitSlices extends Module {
  ConcatNestedAdjacentBitSlices() {
    final a = addInput('a', Logic(width: 8), width: 8);
    final inner = Concat([a[7], a[6], a[5]]).out;
    addOutput('out', width: 5) <= [inner, a[4], a[3]].concat();
  }
}

class ConcatAdjacentRanges extends Module {
  ConcatAdjacentRanges() {
    final a = addInput('a', Logic(width: 8), width: 8);
    addOutput('out', width: 6) <= [a.slice(5, 2), a.slice(1, 0)].concat();
  }
}

class ConcatPackedArrayElementBits extends Module {
  ConcatPackedArrayElementBits(LogicArray arr) {
    final inArr = addInputArray('arr', arr, dimensions: [2, 2]);
    final upper = inArr.elements[1] as LogicArray;
    final lower = inArr.elements[0] as LogicArray;
    addOutput('out', width: 4) <=
        [
          upper.elements[1],
          upper.elements[0],
          lower.elements[1],
          lower.elements[0],
        ].concat();
  }
}

class ConcatUnpackedArrayElements extends Module {
  ConcatUnpackedArrayElements(LogicArray arr) {
    final inArr = addInputArray(
      'arr',
      arr,
      dimensions: [4],
      numUnpackedDimensions: 1,
    );
    addOutput('out', width: 4) <= inArr.elements.reversed.toList().concat();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('concat aliases', () {
    test('Logic concatenation preserves ordering', () {
      final high = Logic(width: 2)..put(0x2);
      final low = Logic(width: 2)..put(0x1);

      expect(
        [high, low].concat().value,
        LogicValue.ofString('1001'),
      );
      expect(
        [low, high].rconcat().value,
        LogicValue.ofString('1001'),
      );
    });

    test('LogicValue concatenation preserves ordering', () {
      final high = LogicValue.ofString('10');
      final low = LogicValue.ofString('01');

      expect([high, low].concat(), LogicValue.ofString('1001'));
      expect([low, high].rconcat(), LogicValue.ofString('1001'));
    });

    test('deprecated aliases preserve concatenation ordering', () {
      final high = LogicValue.ofString('10');
      final low = LogicValue.ofString('01');

      expect([high, low].concat(), LogicValue.ofString('1001'));
      expect([low, high].rconcat(), LogicValue.ofString('1001'));
    });
  });

  group('Bit Range Annotations', () {
    test('variety of element widths with aligned bit ranges', () async {
      final mod = ConcatVariety(Logic(width: 8));
      await mod.build();

      final sv = mod.dumpSystemVerilog();
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

    test('single element concat has no bit range annotations', () async {
      final mod = SingleElementConcat(Logic(width: 8));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

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
      final mod = AllSingleBitConcat();
      await mod.build();

      final sv = mod.dumpSystemVerilog();

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

    test('nested concats with proper annotations', () async {
      final mod = NestedConcat(Logic(width: 4), Logic(width: 3));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      // Should contain annotations for both inner and outer concats
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

    test('concat inlined in expressions maintains annotations', () async {
      final mod = InlinedConcat(Logic(width: 4), Logic(width: 4));
      await mod.build();

      final sv = mod.dumpSystemVerilog();

      // Should have annotations even when concat is part of larger expression
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
      final mod = VariedWidthConcat();
      await mod.build();

      final sv = mod.dumpSystemVerilog();

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
      final largeModule = LargeWidthConcat();
      await largeModule.build();
      final sv = largeModule.dumpSystemVerilog();

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
          ].concat()
        }),
      ];
      await SimCompare.checkFunctionalVector(largeModule, vectors);
      final simResult = SimCompare.iverilogVector(largeModule, vectors);
      expect(simResult, equals(true));
    });
  });

  group('SystemVerilog slice collapsing', () {
    test('collapses descending contiguous bit selects', () async {
      final mod = ConcatAdjacentBitSlices();
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, contains('assign out = {a[7:5],a[2:0]};'));
      expect(sv, isNot(contains('a[7],a[6]')));

      final vectors = [
        for (final value in [0x00, 0xe5, 0x3c, 0xff])
          Vector({
            'a': value
          }, {
            'out': (((value >> 5) & 0x7) << 3) | (value & 0x7),
          }),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('omits braces when the whole concat collapses to one slice', () async {
      final mod = ConcatAllAdjacentBitSlices();
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, contains('assign out = a[7:5];'));
      expect(sv, isNot(contains('assign out = {a[7:5]};')));

      final vectors = [
        for (final value in [0x00, 0xe0, 0xa0, 0xff])
          Vector({'a': value}, {'out': (value >> 5) & 0x7}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('does not collapse ascending bit selects', () async {
      final mod = ConcatAscendingBitSlices();
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, isNot(contains('a[2:0]')));
      expect(sv, contains('a[0]'));
      expect(sv, contains('a[1]'));
      expect(sv, contains('a[2]'));

      final vectors = [
        for (final value in [0x00, 0x05, 0x06, 0xff])
          Vector({
            'a': value
          }, {
            'out': ((value & 0x1) << 2) |
                (((value >> 1) & 0x1) << 1) |
                ((value >> 2) & 0x1),
          }),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('collapses nested concat internals but not across the nested range',
        () async {
      final mod = ConcatNestedAdjacentBitSlices();
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, contains('assign out = {(a[7:5]),a[4:3]};'));
      expect(sv, isNot(contains('a[7:3]')));

      final vectors = [
        for (final value in [0x00, 0xf8, 0xa8, 0xff])
          Vector({'a': value}, {'out': (value >> 3) & 0x1f}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('does not re-collapse adjacent range operands', () async {
      final mod = ConcatAdjacentRanges();
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, contains('assign out = {(a[5:2]),(a[1:0])};'));
      expect(sv, isNot(contains('a[5:0]')));

      final vectors = [
        for (final value in [0x00, 0x15, 0x2a, 0xff])
          Vector({'a': value}, {'out': value & 0x3f}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('collapses packed array element bit selects within each element',
        () async {
      final mod = ConcatPackedArrayElementBits(LogicArray([2, 2], 1));
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, contains('assign out = {arr[1][1:0],arr[0][1:0]};'));
      expect(sv, isNot(contains('arr[1][1],arr[1][0]')));

      final vectors = [
        for (final value in [0x0, 0x5, 0xa, 0xf])
          Vector({'arr': value}, {'out': value}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('does not collapse unpacked array element selects', () async {
      final mod = ConcatUnpackedArrayElements(
        LogicArray([4], 1, numUnpackedDimensions: 1),
      );
      await mod.build();

      final sv =
          SvCleaner.removeConcatAnnotationComments(mod.dumpSystemVerilog());

      expect(sv, isNot(contains('arr[3:0]')));
      expect(sv, contains('arr[3]'));
      expect(sv, contains('arr[2]'));
      expect(sv, contains('arr[1]'));
      expect(sv, contains('arr[0]'));
    });
  });

  test('annotated elements of concat in generated sv', () async {
    final mod = ConcatVariety(Logic(width: 8));
    await mod.build();

    final sv = mod.dumpSystemVerilog();

    expect(sv, contains('''
assign b = {
1'h0, /*    34 */
a, /* 33:26 */
x, /* 25:22 */
(y), /* 21:16 */
5'h3, /* 15:11 */
({
3'h2, /* 10:8 */
a  /*  7:0 */
})  /* 10: 0 */
};  // concat'''));
  });

  group('LogicValue', () {
    test('simple concat', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .concat(),
          equals(LogicValue.ofString('10xz')));
    });
    test('simple rconcat', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .rconcat(),
          equals(LogicValue.ofString('zx01')));
    });
  });
  group('LogicValue of multi-bit', () {
    test('simple concat', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].concat(),
          equals(LogicValue.ofString('10xz')));
    });

    test('simple rconcat', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].rconcat(),
          equals(LogicValue.ofString('xz10')));
    });

    test('64-bit concat', () {
      expect(
          List.generate(
              32,
              (index) => index.isEven
                  ? LogicValue.ofString('10')
                  : LogicValue.ofString('xz')).concat(),
          equals(LogicValue.ofString('10xz' * 16)));
    });
    test('>64-bit concat single concat', () {
      final str1 = '10xz' * 16;
      final str2 = 'xz10' * 10;
      expect([LogicValue.ofString(str2), LogicValue.ofString(str1)].concat(),
          equals(LogicValue.ofString(str2 + str1)));
    });
    test('>64-bit concat', () {
      expect(
          List.generate(
              40,
              (index) => index.isEven
                  ? LogicValue.ofString('10')
                  : LogicValue.ofString('xz')).concat(),
          equals(LogicValue.ofString('10xz' * 20)));
    });

    group('variety of sizes', () {
      test('smaller', () {
        final bits = ['0', '1', 'x', 'z'];
        final concatStrings = List.generate(
            100,
            (index) =>
                bits[index % bits.length] * (index % 17) +
                bits[(index + 1) % bits.length] * (index % 2));
        expect(LogicValue.ofIterable(concatStrings.map(LogicValue.ofString)),
            equals(LogicValue.ofString(concatStrings.reversed.join())));
      });

      test('larger', () {
        final bits = ['0', '1', 'x', 'z'];
        final concatStrings = List.generate(
            1000,
            (index) =>
                bits[index % bits.length] * (index % 71) +
                bits[(index + 1) % bits.length] * (index % 2));
        expect(LogicValue.ofIterable(concatStrings.map(LogicValue.ofString)),
            equals(LogicValue.ofString(concatStrings.reversed.join())));
      });
    });

    group('filled', () {
      test('simple concat', () {
        expect(
            [LogicValue.ofString('1' * 4), LogicValue.ofString('1' * 4)]
                .concat(),
            equals(LogicValue.ofString('1' * 8)));
      });
      test('big concat', () {
        expect(List.generate(100, (index) => LogicValue.one).concat(),
            equals(LogicValue.ofString('1' * 100)));
      });
      test('0-width both concat', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('')].concat(),
            equals(LogicValue.ofString('')));
      });
      test('0-width lhs concat', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('111')].concat(),
            equals(LogicValue.ofString('111')));
      });
      test('0-width rhs concat', () {
        expect([LogicValue.ofString('111'), LogicValue.ofString('')].concat(),
            equals(LogicValue.ofString('111')));
      });
    });

    group('non-filled', () {
      test('0-width both concat', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('')].concat(),
            equals(LogicValue.ofString('')));
      });
      test('0-width lhs concat', () {
        expect([LogicValue.ofString(''), LogicValue.ofString('1zx0')].concat(),
            equals(LogicValue.ofString('1zx0')));
      });
      test('0-width rhs concat', () {
        expect([LogicValue.ofString('1zx0'), LogicValue.ofString('')].concat(),
            equals(LogicValue.ofString('1zx0')));
      });
    });
  });

  group('Logic', () {
    test('simple concat', () async {
      final mod = ConcatModule(Logic());
      await mod.build();
      final vectors = [
        Vector({'a': 0}, {'b': bin('0101')}),
        Vector({'a': 1}, {'b': bin('0111')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('const 0-width concat', () async {
      final mod = ConcatModule(Const(0, width: 0));
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

  test('zero-width concat', () {
    final result = <Logic>[].concat();

    expect(result.isEmpty, isTrue);
    expect(result.value, LogicValue.empty);
  });

  test('concat with one non-zero-width signal skips Concat module', () {
    final a = Logic(name: 'a', width: 4);
    final result = [Const(0, width: 0), a].concat();
    expect(identical(result, a), isTrue);
  });

  test('rconcat with one non-zero-width signal skips Concat module', () {
    final a = Logic(name: 'a', width: 4);
    final result = [a, Const(0, width: 0)].rconcat();
    expect(identical(result, a), isTrue);
  });

  test('zero-width concat module', () async {
    final mod = ConcatEmpty(Logic());
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
