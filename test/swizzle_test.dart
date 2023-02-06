/// Copyright (C) 2022-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// swizzle_test.dart
/// Tests for swizzling values
///
/// 2022 January 6
/// Author: Max Korbel <max.korbel@intel.com>
///

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

void main() {
  tearDown(() async {
    await Simulator.reset();
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
        expect(LogicValue.of(swizzleStrings.map(LogicValue.ofString)),
            equals(LogicValue.ofString(swizzleStrings.reversed.join())));
      });

      test('larger', () {
        final bits = ['0', '1', 'x', 'z'];
        final swizzleStrings = List.generate(
            1000,
            (index) =>
                bits[index % bits.length] * (index % 71) +
                bits[(index + 1) % bits.length] * (index % 2));
        expect(LogicValue.of(swizzleStrings.map(LogicValue.ofString)),
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
}
