// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_test.dart
// Tests for LogicValue
//
// 2021 August 2
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:math';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/logic_value/invalid_random_logic_value_exception.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

// All logicvalues to support trying all possiblities
const allLv = [LogicValue.zero, LogicValue.one, LogicValue.x, LogicValue.z];

// shorten some names to make tests read better
const lv = LogicValue.ofString;
LogicValue large(LogicValue lv) => LogicValue.filled(100, lv);

int repeatedInt(int value, int width, int times) {
  var result = 0;
  for (var i = 0; i < times; i++) {
    result <<= width;
    result |= value;
  }
  return result.toSigned(INT_BITS);
}

void main() {
  test('bin with underscores', () {
    var x = bin('11_1');
    expect(x, equals(7));
    x = bin('0001_0111');
    expect(x, equals(23));
    x = bin('0000_1000_0000');
    expect(x, equals(128));
  });
  group('two input bitwise', () {
    test('and2', () {
      // test z & 1 == x, rest unchanged
      expect(lv('01xz') & lv('1111'), equals(lv('01xx')));
      // Large filled test of * & 1
      for (final v in allLv) {
        expect(large(v) & large(LogicValue.one),
            equals(large(v & LogicValue.one)));
      }
      // Large logicValues test of &
      expect(lv('01xz' * 100) & lv('1111' * 100), equals(lv('01xx' * 100)));
      // test * & 0 = 0
      expect(lv('01xz') & lv('0000'), equals(lv('0000')));
      // try mixing .ofString with .filled
      expect(lv('01xz') & LogicValue.filled(4, LogicValue.zero),
          equals(LogicValue.filled(4, LogicValue.zero)));
    });
  });

  group('LogicValue Misc', () {
    test('reversed', () {
      expect(lv('01xz').reversed, equals(lv('zx10')));
      expect(lv('010').reversed, equals(lv('010')));
      // reverse large values
      expect(lv('01' * 100).reversed, equals(lv('10' * 100)));
      expect(lv('01xz' * 100).reversed, equals(lv('zx10' * 100)));
      // reverse filled
      for (final v in allLv) {
        expect(large(v).reversed, equals(large(v)));
      }
    });
  });

  group('logic value', () {
    test('fromBool', () {
      expect(LogicValue.ofBool(true), equals(LogicValue.one));
      expect(LogicValue.ofBool(false), equals(LogicValue.zero));
      expect(LogicValue.ofBool(true), equals(LogicValue.ofString('1')));
      expect(LogicValue.ofBool(false), equals(LogicValue.ofString('0')));
    });
  });

  group('LogicValue', () {
    test('factory and to methods', () {
      expect(LogicValue.one.toString(includeWidth: false), equals('1'));
      expect(LogicValue.zero.toString(includeWidth: false), equals('0'));
      expect(LogicValue.x.toString(includeWidth: false), equals('x'));
      expect(LogicValue.z.toString(includeWidth: false), equals('z'));
      expect(LogicValue.one.toString(), equals("1'h1"));
      expect(LogicValue.zero.toString(), equals("1'h0"));
      expect(LogicValue.x.toString(), equals("1'bx"));
      expect(LogicValue.z.toString(), equals("1'bz"));
      expect(LogicValue.one.toBool(), equals(true));
      expect(LogicValue.zero.toBool(), equals(false));
      expect(LogicValue.x.toBool, throwsA(isA<Exception>()));
      expect(LogicValue.z.toBool, throwsA(isA<Exception>()));
      expect(LogicValue.one.toInt(), equals(1));
      expect(LogicValue.zero.toInt(), equals(0));
      expect(LogicValue.x.toInt, throwsA(isA<Exception>()));
      expect(LogicValue.z.toInt, throwsA(isA<Exception>()));
      expect(LogicValue.ofString(''), equals(LogicValue.ofInt(1, 0)));
      expect(
          <LogicValue>[].swizzle(), equals(LogicValue.ofBigInt(BigInt.two, 0)));
    });

    test('big unsigned int string', () {
      expect(LogicValue.ofString('1' * INT_BITS),
          equals(LogicValue.ofInt(-1, INT_BITS)));
    });

    test('-1 int vs. 64 1s for big width', () {
      expect(LogicValue.ofInt(-1, 100),
          LogicValue.ofBigInt((BigInt.one << INT_BITS) - BigInt.one, 100));
    });

    test('invalid string ofString', () {
      expect(() => LogicValue.ofString('-1'),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.ofString('a'),
          throwsA(isA<LogicValueConstructionException>()));
    });

    test('LogicValue Construction', () {
      expect(LogicValue.of(1, fill: true, width: 2),
          equals(LogicValue.filled(2, LogicValue.one)));
      expect(LogicValue.of(BigInt.one, fill: true, width: 2),
          equals(LogicValue.filled(2, LogicValue.one)));
      expect(LogicValue.of(true, fill: true), equals(LogicValue.one));
      expect(LogicValue.of('z'), equals(LogicValue.z));
      expect(LogicValue.of('1', fill: true, width: 4),
          equals(LogicValue.filled(4, LogicValue.one)));
      expect(LogicValue.of('1111'), equals(LogicValue.ofString('1111')));
      expect(
          LogicValue.of('1111', width: 2), equals(LogicValue.ofString('11')));
      expect(LogicValue.of('1111', width: 8),
          equals(LogicValue.ofString('00001111')));
      expect(LogicValue.of([LogicValue.zero], width: 4),
          equals(LogicValue.filled(4, LogicValue.zero)));
      expect(LogicValue.of([LogicValue.one, LogicValue.x]),
          equals(LogicValue.ofIterable([LogicValue.one, LogicValue.x])));
      expect(
          LogicValue.of(
              [LogicValue.one, LogicValue.x, LogicValue.ofString('1010')],
              width: 1),
          equals(LogicValue.one));
      expect(
          LogicValue.of(
              [LogicValue.one, LogicValue.x, LogicValue.ofString('1010')],
              width: 8),
          equals(LogicValue.ofString('001010x1')));

      LogicValue.filled(4, LogicValue.one);

      // Exceptions
      expect(() => LogicValue.filled(1, LogicValue.filled(5, LogicValue.one)),
          throwsA(isA<Exception>()));
      LogicValue.of(1, fill: true, width: 2);
      expect(() => LogicValue.of(45),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of(45, fill: true, width: 2),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of(BigInt.from(1234567)),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of(BigInt.from(1234567), fill: true, width: 2),
          throwsA(isA<LogicValueConstructionException>()));
      expect(
          () => LogicValue.of(LogicValue.filled(2, LogicValue.zero),
              fill: true, width: 4),
          throwsA(isA<LogicValueConstructionException>()));
      expect(
          () =>
              LogicValue.of(LogicValue.filled(2, LogicValue.zero), fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(
          () =>
              LogicValue.of(LogicValue.filled(1, LogicValue.zero), fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of('22', fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of('1', fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of([LogicValue.zero, LogicValue.one], fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of([LogicValue.zero], fill: true),
          throwsA(isA<LogicValueConstructionException>()));
      expect(() => LogicValue.of(null),
          throwsA(isA<LogicValueConstructionException>()));
      expect(
          () => LogicValue.of(Null), throwsA(isA<UnsupportedTypeException>()));
    });

    test('unary', () {
      expect(LogicValue.one.isValid, equals(true));
      expect(LogicValue.zero.isValid, equals(true));
      expect(LogicValue.x.isValid, equals(false));
      expect(LogicValue.z.isValid, equals(false));
      expect(~LogicValue.one, equals(LogicValue.zero));
      expect(~LogicValue.zero, equals(LogicValue.one));
      expect(~LogicValue.x, equals(LogicValue.x));
      expect(~LogicValue.z, equals(LogicValue.x));
    });
    test('and', () {
      expect(LogicValue.one & LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.one & LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.one & LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.one & LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.zero & LogicValue.one, equals(LogicValue.zero));
      expect(LogicValue.zero & LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.zero & LogicValue.x, equals(LogicValue.zero));
      expect(LogicValue.zero & LogicValue.z, equals(LogicValue.zero));
      expect(LogicValue.x & LogicValue.one, equals(LogicValue.x));
      expect(LogicValue.x & LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.x & LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.x & LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.z & LogicValue.one, equals(LogicValue.x));
      expect(LogicValue.z & LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.z & LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.z & LogicValue.z, equals(LogicValue.x));
    });
    test('or', () {
      expect(LogicValue.one | LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.one | LogicValue.zero, equals(LogicValue.one));
      expect(LogicValue.one | LogicValue.x, equals(LogicValue.one));
      expect(LogicValue.one | LogicValue.z, equals(LogicValue.one));
      expect(LogicValue.zero | LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.zero | LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.zero | LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.zero | LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.x | LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.x | LogicValue.zero, equals(LogicValue.x));
      expect(LogicValue.x | LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.x | LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.z | LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.z | LogicValue.zero, equals(LogicValue.x));
      expect(LogicValue.z | LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.z | LogicValue.z, equals(LogicValue.x));
    });
    test('xor', () {
      expect(LogicValue.one ^ LogicValue.one, equals(LogicValue.zero));
      expect(LogicValue.one ^ LogicValue.zero, equals(LogicValue.one));
      expect(LogicValue.one ^ LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.one ^ LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.zero ^ LogicValue.one, equals(LogicValue.one));
      expect(LogicValue.zero ^ LogicValue.zero, equals(LogicValue.zero));
      expect(LogicValue.zero ^ LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.zero ^ LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.x ^ LogicValue.one, equals(LogicValue.x));
      expect(LogicValue.x ^ LogicValue.zero, equals(LogicValue.x));
      expect(LogicValue.x ^ LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.x ^ LogicValue.z, equals(LogicValue.x));
      expect(LogicValue.z ^ LogicValue.one, equals(LogicValue.x));
      expect(LogicValue.z ^ LogicValue.zero, equals(LogicValue.x));
      expect(LogicValue.z ^ LogicValue.x, equals(LogicValue.x));
      expect(LogicValue.z ^ LogicValue.z, equals(LogicValue.x));
    });
    test('==', () {
      expect(LogicValue.one == LogicValue.one, equals(true));
      expect(LogicValue.one == LogicValue.zero, equals(false));
      expect(LogicValue.one == LogicValue.x, equals(false));
      expect(LogicValue.one == LogicValue.z, equals(false));
      expect(LogicValue.zero == LogicValue.one, equals(false));
      expect(LogicValue.zero == LogicValue.zero, equals(true));
      expect(LogicValue.zero == LogicValue.x, equals(false));
      expect(LogicValue.zero == LogicValue.z, equals(false));
      expect(LogicValue.x == LogicValue.one, equals(false));
      expect(LogicValue.x == LogicValue.zero, equals(false));
      expect(LogicValue.x == LogicValue.x, equals(true));
      expect(LogicValue.x == LogicValue.z, equals(false));
      expect(LogicValue.z == LogicValue.one, equals(false));
      expect(LogicValue.z == LogicValue.zero, equals(false));
      expect(LogicValue.z == LogicValue.x, equals(false));
      expect(LogicValue.z == LogicValue.z, equals(true));
    });
    test('isPosEdge', () {
      expect(
          LogicValue.isPosedge(LogicValue.one, LogicValue.zero), equals(false));
      expect(
          LogicValue.isPosedge(LogicValue.zero, LogicValue.one), equals(true));
      expect(
          LogicValue.isPosedge(LogicValue.x, LogicValue.one,
              ignoreInvalid: true),
          equals(false));
      expect(
          LogicValue.isPosedge(LogicValue.one, LogicValue.z,
              ignoreInvalid: true),
          equals(false));
      expect(() => LogicValue.isPosedge(LogicValue.x, LogicValue.one),
          throwsA(isA<Exception>()));
      expect(() => LogicValue.isPosedge(LogicValue.one, LogicValue.z),
          throwsA(isA<Exception>()));
    });
    test('isNegEdge', () {
      expect(
          LogicValue.isNegedge(LogicValue.one, LogicValue.zero), equals(true));
      expect(
          LogicValue.isNegedge(LogicValue.zero, LogicValue.one), equals(false));
      expect(
          LogicValue.isNegedge(LogicValue.x, LogicValue.one,
              ignoreInvalid: true),
          equals(false));
      expect(
          LogicValue.isNegedge(LogicValue.one, LogicValue.z,
              ignoreInvalid: true),
          equals(false));
      expect(() => LogicValue.isNegedge(LogicValue.x, LogicValue.one),
          throwsA(isA<Exception>()));
      expect(() => LogicValue.isNegedge(LogicValue.one, LogicValue.z),
          throwsA(isA<Exception>()));
    });
  });

  group('two input bitwise', () {
    test('and2', () {
      expect(
          // test all possible combinations (and fromString)
          LogicValue.ofString('00001111xxxxzzzz') &
              LogicValue.ofString('01xz01xz01xz01xz'),
          equals(LogicValue.ofString('000001xx0xxx0xxx')));
      expect(
          // test filled
          LogicValue.filled(100, LogicValue.zero) &
              LogicValue.filled(100, LogicValue.one),
          equals(LogicValue.filled(100, LogicValue.zero)));
      expect(
          // test length mismatch
          () => LogicValue.ofString('0') & LogicValue.ofString('01'),
          throwsA(isA<Exception>()));
      expect(
          // test for _SmallLogicValue case condition
          LogicValue.filled(4, LogicValue.x) & LogicValue.ofInt(5, 4),
          equals(LogicValue.ofString('0x0x')));
      expect(
          // test for _SmallLogicValue case condition
          LogicValue.filled(4, LogicValue.x) | LogicValue.ofInt(5, 4),
          equals(LogicValue.ofString('x1x1')));
      expect(
          // test for _BigLogicValue case condition
          LogicValue.filled(65, LogicValue.x) & LogicValue.ofInt(55, 65),
          equals(LogicValue.ofString('${'0' * 59}xx0xxx')));
    });

    test('or2', () {
      expect(
          // test all possible combinations
          LogicValue.ofString('00001111xxxxzzzz') |
              LogicValue.ofString('01xz01xz01xz01xz'),
          equals(LogicValue.ofString('01xx1111x1xxx1xx')));
      expect(
          // test ofInt
          LogicValue.ofInt(1, 32) | LogicValue.ofInt(0, 32),
          equals(LogicValue.ofInt(1, 32)));
      expect(
          // test ofBigInt - success
          LogicValue.ofBigInt(BigInt.one, 65) |
              LogicValue.ofBigInt(BigInt.one, 65),
          equals(LogicValue.ofBigInt(BigInt.one, 65)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.one, 32) |
              LogicValue.ofBigInt(BigInt.zero, 32),
          equals(LogicValue.ofInt(1, 32)));
      expect(
          // test ofBigInt
          LogicValue.of(BigInt.one, fill: true, width: 65) |
              LogicValue.ofBigInt(BigInt.from(1), 65),
          equals(LogicValue.filled(65, LogicValue.one)));
      expect(
          // test of filled
          LogicValue.of('01xz', width: 65) |
              LogicValue.of(BigInt.parse('1111'), width: 65),
          equals(LogicValue.ofBigInt(BigInt.from(1111), 65)));
      expect(
          // test of filled - SmallLogicValue
          LogicValue.of('zzzz', width: 4) | LogicValue.of('00zz', width: 4),
          equals(LogicValue.filled(4, LogicValue.x)));
      expect(
          // test of filled - BigLogicValue
          LogicValue.filled(65, LogicValue.z) |
              LogicValue.of('1010', width: 65),
          equals(LogicValue.ofString('${'x' * 59}xx1x1x')));
    });

    test('xor2', () {
      expect(
          // test all possible combinations
          LogicValue.ofString('00001111xxxxzzzz') ^
              LogicValue.ofString('01xz01xz01xz01xz'),
          equals(LogicValue.ofString('01xx10xxxxxxxxxx')));
      expect(
          // test from Iterable
          LogicValue.ofIterable([LogicValue.one, LogicValue.zero]) ^
              LogicValue.ofIterable([LogicValue.one, LogicValue.zero]),
          equals(LogicValue.ofIterable([LogicValue.zero, LogicValue.zero])));
      expect(
          // test of filled SmallLogicValue - 0
          LogicValue.filled(2, LogicValue.zero) ^ LogicValue.ofString('01'),
          equals(LogicValue.ofString('01')));
      expect(
          // test of filled BigLogicValue - 0
          LogicValue.filled(65, LogicValue.zero) ^
              LogicValue.ofBigInt(BigInt.from(5), 65),
          equals(LogicValue.ofBigInt(BigInt.from(5), 65)));
      expect(
          // test of filled SmallLogicValue - 1
          LogicValue.filled(2, LogicValue.one) ^ LogicValue.ofString('01'),
          equals(LogicValue.ofString('10')));
      expect(
          // test of filled BigLogicValue - 1
          LogicValue.filled(65, LogicValue.one) ^
              LogicValue.ofBigInt(BigInt.zero, 65),
          equals(LogicValue.filled(65, LogicValue.one)));
      expect(
          // test of filled BigLogicValue - 1
          LogicValue.filled(65, LogicValue.one) ^
              LogicValue.ofString('${'1' * 61}0000'),
          equals(LogicValue.of(BigInt.from(15), width: 65)));

      // test filled xor with invalid
      expect(
          LogicValue.filled(25, LogicValue.z) ^
              LogicValue.filled(25, LogicValue.z),
          LogicValue.filled(25, LogicValue.x));
    });

    test('tristate2', () {
      // some constants useful for testing all combinations on small and big
      const a = '00001111xxxxzzzz';
      const b = '01xz01xz01xz01xz';
      const r = '0xx0x1x1xxxx01xz';

      // small logic value
      expect(LogicValue.ofString(a).triState(LogicValue.ofString(b)),
          equals(LogicValue.ofString(r)));

      // big logic value
      const m = 5;
      expect(LogicValue.ofString(a * m).triState(LogicValue.ofString(b * m)),
          equals(LogicValue.ofString(r * m)));

      // filled logic value
      const f = 10;
      for (var i = 0; i < a.length; i++) {
        final ac = a.substring(i, i + 1);
        final bc = b.substring(i, i + 1);
        final rc = r.substring(i, i + 1);
        expect(LogicValue.of(ac * f).triState(LogicValue.of(bc * f)),
            LogicValue.of(rc * f));
      }

      for (var i = 0; i < a.length; i += 4) {
        final ac = a.substring(i, i + 4);
        final bc = b.substring(i, i + 4);
        final rc = r.substring(i, i + 4);

        // filled with small
        expect(LogicValue.ofString(ac).triState(LogicValue.ofString(bc)),
            LogicValue.ofString(rc));

        // filled with big
        expect(
            LogicValue.ofString(ac * m * 4)
                .triState(LogicValue.ofString(bc * m * 4)),
            LogicValue.ofString(rc * m * 4));
      }
    });
  });

  test('LogicValue.of example', () {
    final it = [LogicValue.zero, LogicValue.x, LogicValue.ofString('01xz')];
    final lv = LogicValue.ofIterable(it);
    expect(lv.toString(), equals("6'b01xzx0"));
  });

  group('LogicValue toString', () {
    const intBitsMinus4 = INT_BITS - 4;

    test('1 bit', () {
      expect(LogicValue.one.toString(), "1'h1");
    });

    test('1 bit invalid', () {
      expect(LogicValue.x.toString(), "1'bx");
    });

    test('<64-bit positive', () {
      expect(LogicValue.ofInt(0x1234, intBitsMinus4).toString(),
          "$intBitsMinus4'h1234");
    });

    test('<64-bit negative', () {
      expect(LogicValue.ofInt(-1, intBitsMinus4).toString(),
          "$intBitsMinus4'h${'f' * (intBitsMinus4 ~/ 4)}");
    });

    test('64-bit positive', () {
      expect(LogicValue.ofInt(0x1234, INT_BITS).toString(), "$INT_BITS'h1234");
    });

    test('64-bit negative', () {
      expect(LogicValue.ofInt(-11, INT_BITS).toString(),
          "$INT_BITS'h${'f' * (INT_BITS ~/ 4 - 1)}5");
    });

    test('>64-bit positive', () {
      expect(
          LogicValue.ofBigInt(BigInt.parse('0x5faaaaaaa00000005'), 68)
              .toString(),
          "68'h5faaaaaaa00000005");
    });

    test('>64-bit negative', () {
      expect(
          LogicValue.ofBigInt(BigInt.parse('0xffaaaaaaa00000005'), 68)
              .toString(),
          "68'hffaaaaaaa00000005");
    });

    test('include width', () {
      expect(
          LogicValue.ofInt(0x55, 8).toString(includeWidth: false), '01010101');
    });
  });

  group('unary operations (including "to")', () {
    test('toMethods', () {
      expect(
          // toString
          LogicValue.ofString('0').toString(),
          equals("1'h0"));
      expect(
          // toList
          LogicValue.ofString('0101').toList(),
          equals([
            LogicValue.one,
            LogicValue.zero,
            LogicValue.one,
            LogicValue.zero
          ]) // NOTE: "reversed" by construction (see function definition)
          );
      expect(
          // toInt - valid
          LogicValue.ofString('111').toInt(),
          equals(7));
      expect(
          // toInt - invalid
          () => LogicValue.filled(65, LogicValue.one).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValue.filled(65, LogicValue.one).toBigInt(),
          equals(BigInt.parse('36893488147419103231')));
    });

    group('large-width toInt', () {
      test('big', () {
        expect(LogicValue.ofInt(1234, 100).toInt(), 1234);
        expect(() => LogicValue.ofBigInt(-BigInt.two, 100).toInt(),
            throwsA(isA<InvalidTruncationException>()));
        expect(() => LogicValue.ofString('x' * 10 + '0' * 90).toInt(),
            throwsA(isA<InvalidValueOperationException>()));
      });

      test('filled', () {
        expect(LogicValue.ofInt(0, 100).toInt(), 0);
        expect(() => LogicValue.ofBigInt(-BigInt.one, 100).toInt(),
            throwsA(isA<InvalidTruncationException>()));
        expect(() => LogicValue.ofString('z' * 100).toInt(),
            throwsA(isA<InvalidValueOperationException>()));
      });
    });

    test('properties+indexing', () {
      expect(
          // index - LSb
          LogicValue.ofString('0101')[0],
          equals(LogicValue.one) // NOTE: index 0 refers to LSb
          );
      expect(
          // index - MSb
          LogicValue.ofString('0101')[3],
          equals(LogicValue.zero) // NOTE: index (length-1) refers to MSb
          );
      expect(
          // large
          LogicValue.ofString('01xz' * 50)[101],
          equals(LogicValue.x));
      expect(
          // filled
          LogicValue.ofString('1111')[2],
          equals(LogicValue.one));
      expect(
          // index - out of range
          () => LogicValue.ofString('0101')[10],
          throwsA(isA<IndexError>()));
      expect(
          // index - out of range
          () => LogicValue.ofString('0101')[-5],
          throwsA(isA<IndexError>()));
      expect(
          // index - negative
          LogicValue.ofString('0111')[-1],
          equals(LogicValue.zero));
      expect(
          // index - negative
          LogicValue.ofString('0100')[-2],
          equals(LogicValue.one));
      expect(
          // reversed
          LogicValue.ofString('0101').reversed,
          equals(LogicValue.ofString('1010')));
      expect(
          // getRange - good inputs
          LogicValue.ofString('0101').getRange(0, 2),
          equals(LogicValue.ofString('01')));
      expect(
          // getRange - slice from range 1
          LogicValue.ofString('0101').getRange(1),
          equals(LogicValue.ofString('010')));
      expect(
          // getRange - slice from negative range
          LogicValue.ofString('0101').getRange(-2),
          equals(LogicValue.ofString('01')));
      expect(
          // getRange - negative end index and start < end
          LogicValue.ofString('0101').getRange(1, -2),
          LogicValue.zero);
      expect(
          // getRange - negative end index and start < end
          LogicValue.ofString('0101').getRange(-3, 4),
          equals(LogicValue.ofString('010')));
      expect(
          // getRange - negative end index and start > end - error! start must
          // be less than end
          () => LogicValue.ofString('0101').getRange(-1, -2),
          throwsA(isA<RangeError>()));
      expect(
          // getRange - same index results zero width value
          LogicValue.ofString('0101').getRange(-1, -1),
          LogicValue.ofString(''));
      expect(
          // getRange - bad inputs start > end
          () => LogicValue.ofString('0101').getRange(2, 1),
          throwsA(isA<RangeError>()));
      expect(
          // getRange - bad inputs end > length-1
          () => LogicValue.ofString('0101').getRange(0, 7),
          throwsA(isA<RangeError>()));
      expect(LogicValue.ofString('xz01').slice(2, 1),
          equals(LogicValue.ofString('z0')));
      expect(LogicValue.ofString('xz01').slice(-2, -3),
          equals(LogicValue.ofString('z0')));
      expect(LogicValue.ofString('xz01').slice(1, 3),
          equals(LogicValue.ofString('0zx')));
      expect(LogicValue.ofString('xz01').slice(-3, -1),
          equals(LogicValue.ofString('0zx')));
      expect(LogicValue.ofString('xz01').slice(-2, -2),
          equals(LogicValue.ofString('z')));
      expect(
          // isValid - valid
          LogicValue.ofString('0101').isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValue.ofString('01x1').isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValue.ofString('01z1').isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValue.ofString('zzzz').isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValue.ofString('zzz1').isFloating,
          equals(false));
    });
  });

  group('shifts', () {
    test('basic', () {
      expect(
          // sll
          LogicValue.ofString('1111') << 2,
          equals(LogicValue.ofString('1100')));
      expect(
          // sra
          LogicValue.ofString('1111') >> 2,
          equals(LogicValue.ofString('1111')));
      expect(
          // srl
          LogicValue.ofString('1111') >>> 2,
          equals(LogicValue.ofString('0011')));
    });

    test('small int boundary shift right logical', () {
      const lower = 14;
      const upper = INT_BITS - lower;
      const shamt = 20;
      const remainder = INT_BITS - shamt;

      // at boundary
      expect((LogicValue.ofInt(-5, INT_BITS) >>> 24).toInt(),
          repeatedInt(0xf, 4, (INT_BITS - 24) ~/ 4));
      expect(LogicValue.ofString('x' * upper + '0' * lower) >>> shamt,
          LogicValue.ofString('0' * shamt + 'x' * remainder));
      expect(LogicValue.ofString('z' * upper + '0' * lower) >>> shamt,
          LogicValue.ofString('0' * shamt + 'z' * remainder));

      // below boundary
      expect((LogicValue.ofInt(-5, INT_BITS - 4) >>> 24).toInt(),
          repeatedInt(0xf, 4, (INT_BITS - 4 - 24) ~/ 4));
      expect(LogicValue.ofString('x' * upper + '0' * (lower - 1)) >>> shamt,
          LogicValue.ofString('0' * shamt + 'x' * (remainder - 1)));
      expect(LogicValue.ofString('z' * upper + '0' * (lower - 1)) >>> shamt,
          LogicValue.ofString('0' * shamt + 'z' * (remainder - 1)));
    });

    test('small int boundary shift left logical', () {
      const upper = 14;
      const lower = INT_BITS - upper;
      const shamt = 20;
      const remainder = INT_BITS - shamt;

      // at boundary
      expect(
          (LogicValue.ofInt(-1, INT_BITS) << shamt).toInt(),
          (repeatedInt(0xf, 4, (INT_BITS - shamt) ~/ 4) << shamt)
              .toSigned(INT_BITS));
      expect(LogicValue.ofString('0' * upper + 'x' * lower) << shamt,
          LogicValue.ofString('x' * remainder + '0' * shamt));
      expect(LogicValue.ofString('0' * upper + 'z' * lower) << shamt,
          LogicValue.ofString('z' * remainder + '0' * shamt));

      // below boundary
      expect((LogicValue.ofInt(-1, 28) << 24).toInt(), 0xf000000);
      expect(LogicValue.ofString('0' * upper + 'x' * (lower - 1)) << shamt,
          LogicValue.ofString('x' * (remainder - 1) + '0' * shamt));
      expect(LogicValue.ofString('0' * upper + 'z' * (lower - 1)) << shamt,
          LogicValue.ofString('z' * (remainder - 1) + '0' * shamt));
    });

    test('small int boundary shift right arithmetic', () {
      const lower = 14;
      const upper = INT_BITS - lower;
      const shamt1 = 20;
      const shamt2 = 10;
      const remainder = INT_BITS - shamt1;

      // at boundary
      expect((LogicValue.ofInt(0xffff, INT_BITS) >> 8).toInt(), 0xff);
      expect((LogicValue.ofInt(-5, INT_BITS) >> shamt1).toInt(), -1);
      expect(LogicValue.ofString('x' * upper + '0' * lower) >> shamt1,
          LogicValue.filled(INT_BITS, LogicValue.x));
      expect(LogicValue.ofString('x' * upper + '0' * lower) >> shamt2,
          LogicValue.ofString('x' * (upper + shamt2) + '0' * 4));
      expect(LogicValue.ofString('z' * upper + '0' * lower) >> shamt1,
          LogicValue.ofString('x' * shamt1 + 'z' * remainder));

      // below boundary
      expect((LogicValue.ofInt(0xffff, INT_BITS - 1) >> 8).toInt(), 0xff);
      expect((LogicValue.ofInt(-5, INT_BITS - 1) >> shamt1).toInt(), -1 >>> 1);
      expect(LogicValue.ofString('x' * upper + '0' * (lower - 1)) >> shamt1,
          LogicValue.filled(INT_BITS - 1, LogicValue.x));
      expect(LogicValue.ofString('x' * upper + '0' * (lower - 1)) >> shamt2,
          LogicValue.ofString('x' * (upper + shamt2) + '0' * 3));
      expect(LogicValue.ofString('z' * upper + '0' * (lower - 1)) >> shamt1,
          LogicValue.ofString('x' * shamt1 + 'z' * (remainder - 1)));
    });

    test('big shift right logical', () {
      expect((LogicValue.ofInt(-5, INT_BITS + 1) >>> 28).toInt(),
          repeatedInt(0xf, 4, (INT_BITS - 28) ~/ 4));
      expect(LogicValue.ofBigInt(-BigInt.two, 128) >>> 96,
          LogicValue.ofInt(0xffffffff, 128));
      expect(LogicValue.ofString('x' * 51 + '0' * 14) >>> 20,
          LogicValue.ofString('0' * 20 + 'x' * 45));
      expect(LogicValue.ofString('z' * 51 + '0' * 14) >>> 20,
          LogicValue.ofString('0' * 20 + 'z' * 45));
    });

    test('big shift left logical', () {
      expect((LogicValue.ofInt(-1, INT_BITS + 1) << 20).toBigInt(),
          (-BigInt.one).toUnsigned(INT_BITS + 1 - 20) << 20);
      expect((LogicValue.ofBigInt(-BigInt.two, 128) << 20).toBigInt(),
          (-BigInt.two).toUnsigned(128 - 20) << 20);
      expect(LogicValue.ofString('0' * 15 + 'x' * 50) << 20,
          LogicValue.ofString('x' * 45 + '0' * 20));
      expect(LogicValue.ofString('0' * 15 + 'z' * 50) << 20,
          LogicValue.ofString('z' * 45 + '0' * 20));
    });

    test('big shift right arithmetic', () {
      expect((LogicValue.ofInt(0xffff, 65) >> 8).toInt(), 0xff);
      expect((LogicValue.ofInt(-5, 65) >> 20).toInt(), -5 >>> 20);
      expect(LogicValue.ofBigInt(-BigInt.two, 128) >> 3,
          LogicValue.ofBigInt(-BigInt.one, 128));
      expect(LogicValue.ofString('x' * 51 + '0' * 14) >> 20,
          LogicValue.filled(65, LogicValue.x));
      expect(LogicValue.ofString('x' * 51 + '0' * 14) >> 10,
          LogicValue.ofString('x' * 61 + '0' * 4));
      expect(LogicValue.ofString('z' * 51 + '0' * 14) >> 20,
          LogicValue.ofString('x' * 20 + 'z' * 45));
    });

    test('filled shift right logical', () {
      for (var width = 62; width < 67; width++) {
        expect(LogicValue.filled(width, LogicValue.one) >>> 20,
            LogicValue.ofString('0' * 20 + '1' * (width - 20)));
        expect(LogicValue.filled(width, LogicValue.zero) >>> 20,
            LogicValue.ofString('0' * width));
        expect(LogicValue.filled(width, LogicValue.x) >>> 20,
            LogicValue.ofString('0' * 20 + 'x' * (width - 20)));
        expect(LogicValue.filled(width, LogicValue.z) >>> 20,
            LogicValue.ofString('0' * 20 + 'z' * (width - 20)));
      }
    });

    test('filled shift left logical', () {
      for (var width = 62; width < 67; width++) {
        expect(LogicValue.filled(width, LogicValue.one) << 20,
            LogicValue.ofString('1' * (width - 20) + '0' * 20));
        expect(LogicValue.filled(width, LogicValue.zero) << 20,
            LogicValue.ofString('0' * width));
        expect(LogicValue.filled(width, LogicValue.x) << 20,
            LogicValue.ofString('x' * (width - 20) + '0' * 20));
        expect(LogicValue.filled(width, LogicValue.z) << 20,
            LogicValue.ofString('z' * (width - 20) + '0' * 20));
      }
    });

    test('filled shift right arithmetic', () {
      for (var width = 62; width < 67; width++) {
        expect(LogicValue.filled(width, LogicValue.one) >> 20,
            LogicValue.ofString('1' * width));
        expect(LogicValue.filled(width, LogicValue.zero) >> 20,
            LogicValue.ofString('0' * width));
        expect(LogicValue.filled(width, LogicValue.x) >> 20,
            LogicValue.ofString('x' * width));
        expect(LogicValue.filled(width, LogicValue.z) >> 20,
            LogicValue.ofString('x' * 20 + 'z' * (width - 20)));
      }
    });

    test('more than width', () {
      expect(LogicValue.ofInt(10, 25) >> 25, LogicValue.ofInt(0, 25));
      expect(LogicValue.ofInt(10, 50) >> 50, LogicValue.ofInt(0, 50));
      expect(LogicValue.ofInt(10, 64) >> 65, LogicValue.ofInt(0, 64));
      expect(LogicValue.ofInt(10, 80) >> 100, LogicValue.ofInt(0, 80));
      expect(
          LogicValue.ofString('x' * 80) >> 100, LogicValue.ofString('x' * 80));
      expect(
          LogicValue.ofString('z' * 80) >> 100, LogicValue.ofString('x' * 80));
    });

    test('huge left', () {
      expect((LogicValue.ofInt(45, 20) << -1).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) << -1).toInt(), 0);
      expect((LogicValue.ofInt(45, 64) << -4).toInt(), 0);
      expect((LogicValue.ofInt(45, 80) << -4).toInt(), 0);
      expect((LogicValue.ofInt(-39, 80) << -4).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) << -4).toInt(), 0);

      expect((LogicValue.ofInt(45, 20) << BigInt.from(-1)).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) << BigInt.from(-1)).toInt(), 0);
      expect((LogicValue.ofInt(45, 64) << BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(45, 80) << BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 80) << BigInt.from(-7)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) << BigInt.from(-9)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) << (BigInt.one << 80)).toInt(), 0);
    });

    test('huge right', () {
      expect((LogicValue.ofInt(45, 20) >>> -4).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) >>> -4).toInt(), 0);
      expect((LogicValue.ofInt(45, 64) >>> -4).toInt(), 0);
      expect((LogicValue.ofInt(45, 80) >>> -4).toInt(), 0);
      expect((LogicValue.ofInt(-39, 80) >>> -4).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) >>> -4).toInt(), 0);

      expect((LogicValue.ofInt(45, 20) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(45, 64) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(45, 80) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 80) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) >>> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(-39, 60) >>> (BigInt.one << 80)).toInt(), 0);
    });

    test('huge right arithmetic', () {
      expect((LogicValue.ofInt(45, 20) >> -1).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) >> -1).toInt(), 0);
      expect((LogicValue.ofInt(-45, INT_BITS) >> -12).toInt(), -1);
      expect((LogicValue.ofInt(-45, 8) >> -18).toInt(), 0xff);
      expect((LogicValue.ofInt(45, 80) >> -1).toInt(), 0);
      expect((LogicValue.ofInt(-45, 128) >> -18).and().toBool(), false);
      expect((LogicValue.ofBigInt(BigInt.from(-45), 128) >> -18).and().toBool(),
          true);

      expect((LogicValue.ofInt(45, 20) >> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(45, 32) >> BigInt.from(-4)).toInt(), 0);
      expect(
          (LogicValue.ofInt(-45, INT_BITS) >> BigInt.from(-4))
              .toInt()
              .toSigned(INT_BITS),
          -1);
      expect((LogicValue.ofInt(-45, 8) >> BigInt.from(-4)).toInt(), 0xff);
      expect((LogicValue.ofInt(45, 80) >> BigInt.from(-4)).toInt(), 0);
      expect((LogicValue.ofInt(-45, 128) >> BigInt.from(-4)).and().toBool(),
          false);
      expect(
          (LogicValue.ofBigInt(BigInt.from(-45), 128) >> BigInt.from(-4))
              .and()
              .toBool(),
          true);
      expect((LogicValue.ofInt(45, 80) >> (BigInt.one << 80)).toInt(), 0);
      expect((LogicValue.ofInt(-45, 8) >> (BigInt.one << 80)).toInt(), 0xff);
    });

    test('huge right arithmetic zero', () {
      for (var i = 0; i < 100; i++) {
        expect(
            LogicValue.ofBigInt(BigInt.one << 200 | BigInt.one << 100, i) >>
                (BigInt.one << 100),
            LogicValue.filled(i, LogicValue.zero));
      }
    });

    group('invalid values', () {
      test('shift left', () {
        expect(LogicValue.filled(10, LogicValue.x) << 3,
            LogicValue.ofString('xxxxxxx000'));
        expect(LogicValue.filled(10, LogicValue.x) << (BigInt.one << 80),
            LogicValue.ofString('0000000000'));
      });

      test('shift right', () {
        expect(LogicValue.filled(10, LogicValue.x) >>> 3,
            LogicValue.ofString('000xxxxxxx'));
        expect(LogicValue.filled(10, LogicValue.x) >>> (BigInt.one << 80),
            LogicValue.ofString('0000000000'));
      });

      test('shift right arithmetic', () {
        expect(LogicValue.filled(10, LogicValue.x) >> 3,
            LogicValue.filled(10, LogicValue.x));
        expect(LogicValue.filled(10, LogicValue.z) >> 3,
            LogicValue.ofString('xxxzzzzzzz'));
        expect(LogicValue.filled(10, LogicValue.x) >> (BigInt.one << 80),
            LogicValue.filled(10, LogicValue.x));
        expect(LogicValue.filled(10, LogicValue.z) >> (BigInt.one << 80),
            LogicValue.filled(10, LogicValue.x));
      });
    });

    test('shift by 0', () {
      expect(LogicValue.filled(10, LogicValue.x) >> 0,
          LogicValue.filled(10, LogicValue.x));
    });

    test('invalid shamt', () {
      expect(
          LogicValue.filled(10, LogicValue.one) >> LogicValue.ofString('0x10'),
          LogicValue.filled(10, LogicValue.x));
    });

    test('unsupported shamt type', () {
      expect(() => LogicValue.filled(10, LogicValue.one) >> Logic(),
          throwsA(isA<UnsupportedTypeException>()));
    });

    test('example large shifts', () {
      expect((LogicValue.filled(INT_BITS, LogicValue.one) >> 2).toInt(),
          (-1 >> 2).toSigned(INT_BITS));
      expect(
          LogicValue.filled(65, LogicValue.one) >>> 10,
          equals([
            LogicValue.filled(10, LogicValue.zero),
            LogicValue.filled(55, LogicValue.one)
          ].swizzle()));
    });
  });

  group('infer width', () {
    test('int', () {
      expect(LogicValue.ofInferWidth(45).width, 6);
    });

    test('bigint', () {
      expect(
          LogicValue.ofInferWidth((BigInt.one << 70) + BigInt.two).width, 71);
    });

    test('negative int', () {
      expect(() => LogicValue.ofInferWidth(-345).width,
          throwsA(isA<LogicValueConstructionException>()));
    });

    test('negative BigInt', () {
      expect(() => LogicValue.ofInferWidth(-BigInt.one),
          throwsA(isA<LogicValueConstructionException>()));
    });

    test('logicvalue', () {
      expect(LogicValue.ofInferWidth(LogicValue.ofString('01010')).width, 5);
    });

    test('unsupported', () {
      expect(() => LogicValue.ofInferWidth(Logic()).width,
          throwsA(isA<UnsupportedTypeException>()));
    });
  });

  group('comparison operations', () {
    test('equalsWithDontCare', () {
      expect(
          // == not equal
          LogicValue.ofString('1010xz')
              .equalsWithDontCare(LogicValue.ofString('10111x')),
          equals(false));
      expect(
          // == equal
          LogicValue.ofString('1010xz')
              .equalsWithDontCare(LogicValue.ofString('101z1x')),
          equals(true));
      expect(
          // == not equal
          LogicValue.ofString('10x1z1')
              .equalsWithDontCare(LogicValue.ofString('10101x')),
          equals(false));
      expect(
          //
          LogicValue.ofString('10x1z1')
              .equalsWithDontCare(LogicValue.ofString('10101x')),
          equals(false));
      expect(
          LogicValue.ofString('10x1z1')
              .equalsWithDontCare(LogicValue.ofString('101x11')),
          equals(true));
    });
    test('equality', () {
      expect(
          // == equal
          LogicValue.ofString('1111') == LogicValue.ofString('1111'),
          equals(true));
      expect(
          // == not equal
          LogicValue.ofString('1111') == LogicValue.ofString('1110'),
          equals(false));
      expect(
          // eq equal
          LogicValue.ofString('1111').eq(LogicValue.ofString('1111')),
          equals(LogicValue.one));
      expect(
          // eq not equal, valid
          LogicValue.ofString('1111').eq(LogicValue.ofString('1110')),
          equals(LogicValue.zero));
      expect(
          // eq not equal, invalid
          LogicValue.ofString('1111').eq(LogicValue.ofString('111x')),
          equals(LogicValue.x));
    });

    test('inequality', () {
      expect(
          // != equal
          LogicValue.ofString('1111') != LogicValue.ofString('1111'),
          equals(false));
      expect(
          // != not equal
          LogicValue.ofString('1111') != LogicValue.ofString('1110'),
          equals(true));
      expect(
          // neq equal
          LogicValue.ofString('1111').neq(LogicValue.ofString('1111')),
          equals(LogicValue.zero));
      expect(
          // neq not equal, valid
          LogicValue.ofString('1111').neq(LogicValue.ofString('1110')),
          equals(LogicValue.one));
      expect(
          // eq not equal, invalid
          LogicValue.ofString('1111').neq(LogicValue.ofString('111x')),
          equals(LogicValue.x));
    });

    test('greater', () {
      expect(
          // >
          LogicValue.ofString('0111') > LogicValue.ofString('0110'),
          equals(LogicValue.one));
      expect(
          // not >
          LogicValue.ofString('0111') > LogicValue.ofString('0111'),
          equals(LogicValue.zero));
      expect(
          // >=
          LogicValue.ofString('0111') >= LogicValue.ofString('0111'),
          equals(LogicValue.one));
      expect(
          // not >=
          LogicValue.ofString('0110') >= LogicValue.ofString('0111'),
          equals(LogicValue.zero));
      expect(
          // x involved
          LogicValue.ofString('0110') >= LogicValue.ofString('011x'),
          equals(LogicValue.x));
      expect(
          // mismatched lengths
          () => LogicValue.ofString('0110') >= LogicValue.ofString('011000'),
          throwsA(isA<Exception>()));
    });

    test('less', () {
      expect(
          // <
          LogicValue.ofString('0111') < 8,
          equals(LogicValue.one));
      expect(
          // not <
          LogicValue.ofString('0111') < 7,
          equals(LogicValue.zero));
      expect(
          // <=
          LogicValue.ofString('0111') <= 7,
          equals(LogicValue.one));
      expect(
          // not <=
          LogicValue.ofString('0110') <= 5,
          equals(LogicValue.zero));
      expect(
          // x involved
          LogicValue.ofString('011x') <= 10,
          equals(LogicValue.x));
    });
  });
  group('arithmetic operations', () {
    test('power', () {
      expect(
          // test ofInt
          LogicValue.ofInt(2, 32).pow(LogicValue.ofInt(0, 32)),
          equals(LogicValue.ofInt(1, 32)));
      expect(
          // test ofInt
          LogicValue.ofInt(3, 32).pow(LogicValue.ofInt(5, 32)),
          equals(LogicValue.ofInt(243, 32)));
      expect(
          // test ofInt
          LogicValue.ofInt(0, 32).pow(LogicValue.ofInt(0, 32)),
          equals(LogicValue.ofInt(1, 32)));
      expect(
          // test int with BigInt
          LogicValue.ofInt(2, 64)
              .pow(LogicValue.ofBigInt(BigInt.parse('10'), 64)),
          equals(LogicValue.ofBigInt(BigInt.from(1024), 64)));

      expect(
          // test BigInt with int
          LogicValue.ofBigInt(BigInt.two, 64).pow(LogicValue.ofInt(10, 64)),
          equals(LogicValue.ofBigInt(BigInt.from(1024), 64)));

      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.from(31), 128)
              .pow(LogicValue.ofBigInt(BigInt.from(21), 128)),
          equals(LogicValue.ofBigInt(
              BigInt.parse('20825506393391550743120420649631'), 128)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.parse('111234234231234523412665554'), 256)
              .pow(LogicValue.ofBigInt(BigInt.from(2), 256)),
          equals(LogicValue.ofBigInt(
              BigInt.parse(
                  '12373054865009146225795242412633846245734343458126916'),
              256)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.zero, 64)
              .pow(LogicValue.ofBigInt(BigInt.zero, 64)),
          equals(LogicValue.ofBigInt(BigInt.one, 64)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.one, 512).pow(LogicValue.ofBigInt(
              BigInt.parse('100000000000000000000000000000000000000'), 512)),
          equals(LogicValue.ofBigInt(BigInt.one, 512)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.zero, 512).pow(LogicValue.ofBigInt(
              BigInt.parse('100000000000000000000000000000000000000'), 512)),
          equals(LogicValue.ofBigInt(BigInt.zero, 512)));
      expect(
          // exception when BigInt exponent won't fit in int
          () => LogicValue.ofBigInt(BigInt.from(2), 512).pow(
              LogicValue.ofBigInt(
                  BigInt.parse('100000000000000000000000000000000000000'),
                  512)),
          throwsA(isA<InvalidTruncationException>()));
      expect(
          //test string
          LogicValue.ofString('000010').pow(LogicValue.ofString('000100')),
          equals(LogicValue.ofString('010000')));
      expect(
          //test invalid exponent input
          LogicValue.ofString('0001').pow(LogicValue.ofString('000x')),
          equals(LogicValue.filled(4, LogicValue.x)));
      expect(
          //test invalid base input
          LogicValue.ofString('001x').pow(LogicValue.ofString('0001')),
          equals(LogicValue.filled(4, LogicValue.x)));
    });

    test('absolute', () {
      expect(
          // test of positive value
          LogicValue.ofInt(2, 32).abs(),
          equals(LogicValue.ofInt(2, 32)));
      expect(
          // test of negative value
          LogicValue.ofInt(-7, 32).abs(),
          equals(LogicValue.ofInt(7, 32)));
      expect(
          // test of zero width
          LogicValue.filled(0, LogicValue.zero).abs(),
          equals(LogicValue.filled(0, LogicValue.zero)));
      expect(
          //test string
          LogicValue.ofString('000010').abs(),
          equals(LogicValue.ofString('000010')));
    });
    test('addsub', () {
      expect(
          // + normal
          LogicValue.ofString('0001') + LogicValue.ofString('0011'),
          equals(LogicValue.ofString('0100')) // 1 + 3 = 4
          );
      expect(
          // - normal
          LogicValue.ofString('0001') - LogicValue.ofString('0001'),
          equals(LogicValue.ofString('0000')) // 1 - 1 = 0
          );
      expect(
          // + overflow
          LogicValue.ofString('1111') + LogicValue.ofString('0001'),
          equals(LogicValue.ofString('0000')));
      expect(
          // - overflow
          LogicValue.ofString('0000') - LogicValue.ofString('0001'),
          equals(LogicValue.ofString('1111')));
      expect(
          // x involved
          LogicValue.ofString('0000') + LogicValue.ofString('111x'),
          equals(LogicValue.ofString('xxxx')));
      expect(
          // length mismatch
          () => LogicValue.ofString('0000') - LogicValue.ofString('000100'),
          throwsA(isA<Exception>()));

      expect(
          // % normal
          LogicValue.ofString('0001') % LogicValue.ofString('0011'),
          equals(LogicValue.ofString('0001')) // 1 % 3 = 1
          );
      expect(
          // % normal
          LogicValue.ofString('0100') % LogicValue.ofString('0010'),
          equals(LogicValue.ofString('0000')) // 4 % 2 = 0
          );
      expect(
          // % 0 mod
          LogicValue.ofString('0000') % LogicValue.ofString('0011'),
          equals(LogicValue.ofString('0000')) // 0 % 3 = 0
          );
      expect(
          // mod-by-0
          LogicValue.ofString('0100') % LogicValue.ofString('0000'),
          equals(LogicValue.ofString('xxxx')));
      expect(
          // % num by num
          LogicValue.ofString('0100') % LogicValue.ofString('0100'),
          equals(LogicValue.ofString('0000')));
    });

    test('muldiv', () {
      expect(
          // * normal
          LogicValue.ofString('0001') * LogicValue.ofString('0011'),
          equals(LogicValue.ofString('0011')) // 1 * 3 = 3
          );
      expect(
          // / normal
          LogicValue.ofString('0100') / LogicValue.ofString('0010'),
          equals(LogicValue.ofString('0010')) // 4 / 2 = 2
          );
      expect(
          // / truncate
          LogicValue.ofString('0100') / LogicValue.ofString('0011'),
          equals(LogicValue.ofString('0001')) // 4 / 3 = 1 (integer division)
          );
      expect(
          // div-by-0
          LogicValue.ofString('0100') / LogicValue.ofString('0000'),
          equals(LogicValue.ofString('xxxx')));
      expect(
          // * overflow
          LogicValue.ofString('0100') * LogicValue.ofString('0100'),
          equals(LogicValue.ofString('0000')));
    });
  });

  group('not and reductions', () {
    test('not', () {
      expect(
          // not - valid
          ~LogicValue.ofString('0100'),
          equals(LogicValue.ofString('1011')));
      expect(
          // not - invalid
          ~LogicValue.ofString('zzxx'),
          equals(LogicValue.ofString('xxxx')));
    });
    test('and', () {
      expect(
          // and - valid
          LogicValue.ofString('0100').and(),
          equals(LogicValue.zero));
      expect(
          // and - valid (1's)
          LogicValue.ofString('1111').and(),
          equals(LogicValue.one));
      expect(
          // and - invalid
          LogicValue.ofString('010x').and(),
          equals(LogicValue.zero));
      expect(
          // and - invalid (1's)
          LogicValue.ofString('111z').and(),
          equals(LogicValue.x));
    });
    test('or', () {
      expect(
          // or - valid
          LogicValue.ofString('0100').or(),
          equals(LogicValue.one));
      expect(
          // or - valid (0's)
          LogicValue.ofString('0000').or(),
          equals(LogicValue.zero));
      expect(
          // or - invalid
          LogicValue.ofString('010x').or(),
          equals(LogicValue.one));
      expect(
          // or - invalid (1's)
          LogicValue.ofString('000z').or(),
          equals(LogicValue.x));
    });
    test('xor', () {
      expect(
          // xor - valid (even)
          LogicValue.ofString('1100').xor(),
          equals(LogicValue.zero));
      expect(
          // xor - valid (odd)
          LogicValue.ofString('1110').xor(),
          equals(LogicValue.one));
      expect(
          // xor - invalid
          LogicValue.ofString('010x').xor(),
          equals(LogicValue.x));
    });
  });
  group('BigLogicValue', () {
    test('overrides', () {
      expect(
          // reversed
          LogicValue.ofString('01' * 100).reversed,
          equals(LogicValue.ofString('10' * 100)));
      expect(
          // isValid - valid
          LogicValue.ofString('01' * 100).isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValue.ofString('0x' * 100).isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValue.ofString('1z' * 100).isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValue.ofString('z' * 100).isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValue.ofString('z1' * 100).isFloating,
          equals(false));
      expect(
          // toInt - always invalid
          () => LogicValue.ofString('11' * 100).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - invalid
          () => LogicValue.ofString('1x' * 100).toBigInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValue.ofString('0' * 100).toBigInt(),
          equals(BigInt.from(0)));
      expect(
          // not - valid
          ~LogicValue.ofString('0' * 100),
          equals(LogicValue.ofString('1' * 100)));
      expect(
          // not - invalid
          ~LogicValue.ofString('z1' * 100),
          equals(LogicValue.ofString('x0' * 100)));
      expect(
          // and - valid
          LogicValue.ofString('01' * 100).and(),
          equals(LogicValue.zero));
      expect(
          // and - valid (1's)
          LogicValue.ofString('1' * 100).and(),
          equals(LogicValue.one));
      expect(
          // and - invalid
          LogicValue.ofString('01x' * 100).and(),
          equals(LogicValue.zero));
      expect(
          // and - invalid (1's)
          LogicValue.ofString('111z' * 100).and(),
          equals(LogicValue.x));
      expect(
          // or - valid
          LogicValue.ofString('01' * 100).or(),
          equals(LogicValue.one));
      expect(
          // or - valid (0's)
          LogicValue.ofString('0' * 100).or(),
          equals(LogicValue.zero));
      expect(
          // or - invalid
          LogicValue.ofString('10x' * 100).or(),
          equals(LogicValue.one));
      expect(
          // or - invalid (1's)
          LogicValue.ofString('0z' * 100).or(),
          equals(LogicValue.x));
      expect(
          // xor - valid (even)
          LogicValue.ofString('1100' * 100).xor(),
          equals(LogicValue.zero));
      expect(
          // xor - valid (odd)
          LogicValue.ofString('1110' * 99).xor(),
          equals(LogicValue.one));
      expect(
          // xor - invalid
          LogicValue.ofString('010x' * 100).xor(),
          equals(LogicValue.x));
      expect(
          // ofInt with >64 bits
          LogicValue.ofInt(3, 512),
          equals(LogicValue.ofBigInt(BigInt.from(3), 512)));
    });
  });
  group('FilledLogicValue', () {
    test('overrides', () {
      expect(
          // reversed
          LogicValue.filled(100, LogicValue.one).reversed,
          equals(LogicValue.filled(100, LogicValue.one)));
      expect(
          // reversed
          LogicValue.filled(100, LogicValue.zero).reversed,
          equals(LogicValue.filled(100, LogicValue.zero)));
      expect(
          // isValid - valid
          LogicValue.filled(100, LogicValue.zero).isValid,
          equals(true));
      expect(
          // isValid - valid
          LogicValue.filled(100, LogicValue.one).isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValue.filled(100, LogicValue.x).isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValue.filled(100, LogicValue.z).isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValue.filled(100, LogicValue.z).isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValue.filled(100, LogicValue.one).isFloating,
          equals(false));
      expect(
          // toInt - invalid
          () => LogicValue.filled(100, LogicValue.one).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toInt - valid
          LogicValue.filled(64, LogicValue.zero).toInt(),
          equals(0));
      expect(
          // toBigInt - invalid
          () => LogicValue.filled(100, LogicValue.x).toBigInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValue.filled(100, LogicValue.zero).toBigInt(),
          equals(BigInt.from(0)));
      expect(
          // not - valid
          ~LogicValue.filled(100, LogicValue.zero),
          equals(LogicValue.filled(100, LogicValue.one)));
      expect(
          // not - valid
          ~LogicValue.filled(100, LogicValue.one),
          equals(LogicValue.filled(100, LogicValue.zero)));
      expect(
          // not - invalid
          ~LogicValue.filled(100, LogicValue.z),
          equals(LogicValue.filled(100, LogicValue.x)));
      expect(
          // and - valid 0
          LogicValue.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // and - valid 1
          LogicValue.filled(100, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // and - invalid x
          LogicValue.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // and - invalid z
          LogicValue.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
      expect(
          // or - valid 0
          LogicValue.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // or - valid 1
          LogicValue.filled(100, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // or - invalid x
          LogicValue.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // or - invalid z
          LogicValue.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
      expect(
          // xor - valid 0
          LogicValue.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // xor - valid 1
          LogicValue.filled(99, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // xor - invalid x
          LogicValue.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // xor - invalid z
          LogicValue.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
    });
  });

  group('64-bit conversions', () {
    test(
        '64-bit LogicValues larger than maximum positive value on integer'
        ' are properly converted when converted from BigInt', () {
      final extraWide = LogicValue.ofBigInt(
        BigInt.parse('f' * 16 + 'f0' * 8, radix: 16),
        128,
      );
      final smaller = extraWide.getRange(0, INT_BITS);

      expect(smaller.toInt(), equals(repeatedInt(0xf0, 8, INT_BITS ~/ 8)));
    });

    test(
        '64-bit BigInts larger than max pos int value constructing'
        ' a LogicValue is correct', () {
      final bigInt64Lv =
          LogicValue.ofBigInt(BigInt.parse('fa' * 8, radix: 16), INT_BITS);

      expect(bigInt64Lv.toInt(), equals(repeatedInt(0xfa, 8, INT_BITS ~/ 8)));
    });

    test('64-bit binary negatives are converted properly with bin', () {
      expect(bin('1110' * (INT_BITS ~/ 4)), repeatedInt(0xe, 4, INT_BITS ~/ 4));
    });
  });

  group('hash and equality', () {
    test('hash', () {
      // thank you to @bbracker-int
      // https://github.com/intel/rohd/issues/206

      const lvEnum = LogicValue.one;
      final lvBool = LogicValue.ofBool(true);
      final lvInt = LogicValue.ofInt(1, 1);
      final lvBigInt = LogicValue.ofBigInt(BigInt.one, 1);
      final lvFilled = LogicValue.filled(1, lvEnum);

      for (final lv in [lvBool, lvInt, lvBigInt, lvFilled]) {
        expect(lv.hashCode, equals(lvEnum.hashCode));
      }
    });

    test('zero-width', () {
      expect(LogicValue.filled(0, LogicValue.one),
          equals(LogicValue.filled(0, LogicValue.zero)));
      expect(LogicValue.filled(0, LogicValue.one).hashCode,
          equals(LogicValue.filled(0, LogicValue.zero).hashCode));
    });
  });
  group('Utility operations', () {
    test('clog2 operation', () {
      expect(LogicValue.ofInt(15, INT_BITS).clog2().toInt(), 4);
      expect(LogicValue.ofInt(16, INT_BITS).clog2().toInt(), 4);
      expect(LogicValue.ofInt(17, INT_BITS).clog2().toInt(), 5);

      expect(
          // int
          LogicValue.ofInt(0, 8).clog2(),
          equals(LogicValue.ofInt(0, 8)));
      expect(
          // int
          LogicValue.ofInt(1, 32).clog2(),
          equals(LogicValue.ofInt(0, 32)));
      expect(
          // int
          LogicValue.ofInt(2, 16).clog2(),
          equals(LogicValue.ofInt(1, 16)));
      expect(
          // int
          LogicValue.ofInt(3, 32).clog2(),
          equals(LogicValue.ofInt(2, 32)));
      expect(
          // int
          LogicValue.ofInt(16, 64).clog2(),
          equals(LogicValue.ofInt(4, 64)));
      expect(
          // int
          LogicValue.ofInt(17, 64).clog2(),
          equals(LogicValue.ofInt(5, 64)));
      expect(
          // int
          LogicValue.ofInt(-1 >>> 1, INT_BITS).clog2(),
          equals(LogicValue.ofInt(INT_BITS - 1, INT_BITS)));
      expect(
          //  BigInt
          LogicValue.ofBigInt(BigInt.zero, 128).clog2(),
          equals(LogicValue.ofBigInt(BigInt.zero, 128)));
      expect(
          //  BigInt
          LogicValue.ofBigInt(BigInt.one, 128).clog2(),
          equals(LogicValue.ofBigInt(BigInt.zero, 128)));
      expect(
          //  BigInt
          LogicValue.ofBigInt(
                  BigInt.parse('100000000000000000000000000000000'), 128)
              .clog2(),
          equals(LogicValue.ofBigInt(BigInt.from(107), 128)));
      expect(
          //  BigInt
          LogicValue.ofBigInt(BigInt.from(3), 32).clog2(),
          equals(LogicValue.ofBigInt(BigInt.from(2), 32)));
      expect(
          // binary string
          LogicValue.ofString('000100').clog2(),
          equals(LogicValue.ofString('000010')));
      expect(
          // x involved in binary string
          LogicValue.ofString('00x0').clog2(),
          equals(LogicValue.ofString('xxxx')));

      //Negative Int
      expect(LogicValue.ofInt(-128, 8).clog2().toInt(), 7);
      expect(LogicValue.ofInt(-127, 8).clog2().toInt(), 8);

      expect(LogicValue.ofInt(-128, INT_BITS).clog2().toInt(), INT_BITS);
      expect(LogicValue.ofInt(-127, INT_BITS).clog2().toInt(), INT_BITS);
      expect(LogicValue.ofInt(-1, INT_BITS).clog2().toInt(), INT_BITS);

      expect(LogicValue.ofInt(-32768, 16).clog2().toInt(), 15);
      expect(LogicValue.ofInt(-32767, 16).clog2().toInt(), 16);
      expect(LogicValue.ofInt(-1, 16).clog2().toInt(), 16);

      expect(LogicValue.ofInt(-2147483648, 32).clog2().toInt(), 31);
      expect(LogicValue.ofInt(-2147483647, 32).clog2().toInt(), 32);
      expect(LogicValue.ofInt(-1, 32).clog2().toInt(), 32);

      //Negative BigInt
      expect(
          LogicValue.ofBigInt(
                  BigInt.parse('-170141183460469231731687303715884105728'), 128)
              .clog2()
              .toBigInt(),
          BigInt.from(127));
      expect(
          LogicValue.ofBigInt(
                  BigInt.parse('-170141183460469231731687303715884105727'), 128)
              .clog2()
              .toBigInt(),
          BigInt.from(128));
      expect(LogicValue.ofBigInt(BigInt.from(-1), 128).clog2().toBigInt(),
          BigInt.from(128));
    });

    test('clog2 with 1 then 0s', () {
      expect(LogicValue.ofInt(1, INT_BITS).clog2().toInt(), 0);
      expect(
          LogicValue.ofInt(bin('1${'0' * (INT_BITS - 1)}'), INT_BITS)
              .clog2()
              .toInt(),
          INT_BITS - 1);

      for (var i = 0; i < INT_BITS; i++) {
        expect(LogicValue.ofInt(oneSllBy(i), i + 1).clog2().toInt(), i);
      }
      for (var i = INT_BITS; i < 3 * INT_BITS; i++) {
        expect(LogicValue.ofBigInt(BigInt.one << i, i + 1).clog2().toInt(), i);
      }
    });
  });

  group('random value generation ', () {
    test('should throw exception when max is not int or BigInt.', () {
      expect(() => Random(5).nextLogicValue(width: 10, max: '10'),
          throwsA(isA<InvalidRandomLogicValueException>()));
      expect(() => Random(5).nextLogicValue(width: 10, max: 10.5),
          throwsA(isA<InvalidRandomLogicValueException>()));
    });

    test('should throw exception when max is less than 0.', () {
      expect(() => Random(5).nextLogicValue(width: 10, max: -1),
          throwsA(isA<InvalidRandomLogicValueException>()));
      expect(() => Random(5).nextLogicValue(width: 10, max: BigInt.from(-10)),
          throwsA(isA<InvalidRandomLogicValueException>()));
    });

    test(
        'should throw exception when max is set when generate random num with'
        ' invalid bits.', () {
      expect(
          () => Random(5).nextLogicValue(
              width: 10,
              includeInvalidBits: true,
              max: LogicValue.ofInt(10, 10)),
          throwsA(isA<InvalidRandomLogicValueException>()));
    });

    test(
        'should return random logic value with invalid bits when '
        'includeInvalidBits is set to true.', () {
      final lvRand =
          Random(5).nextLogicValue(width: 10, includeInvalidBits: true);

      expect(lvRand.toString(), contains('x'));
    });

    test('should return empty LogicValue when width is 0.', () {
      expect(Random(5).nextLogicValue(width: 0), equals(LogicValue.empty));
    });

    test('should return empty LogicValue when max is 0 for int and big int.',
        () {
      final maxBigInt = BigInt.zero;
      const maxInt = 0;
      expect(Random(5).nextLogicValue(width: 10, max: maxInt).toInt(),
          equals(maxInt));

      expect(Random(5).nextLogicValue(width: 80, max: maxBigInt).toBigInt(),
          equals(maxBigInt));
    });

    test(
        'should return random int logic value without invalid bits when'
        ' having different width and max constraint.', () {
      const maxValInt = 8888;

      for (var i = 1; i <= INT_BITS; i++) {
        final lvRand = Random(5).nextLogicValue(width: i);
        final lvRandMaxInt = Random(5).nextLogicValue(width: i, max: maxValInt);
        final lvMaxBigInt = Random(5)
            .nextLogicValue(width: i, max: BigInt.parse('9999999999999999999'));
        final lvMaxIntBigInt =
            Random(5).nextLogicValue(width: i, max: BigInt.from(maxValInt));

        expect(lvRand.toInt(), isA<int>());
        expect(lvRandMaxInt.toInt(), lessThan(maxValInt));
        expect(lvMaxBigInt, equals(Random(5).nextLogicValue(width: i)));
        expect(lvMaxIntBigInt.toInt(), lessThan(maxValInt));
      }
    });

    test(
        'should return random big integer logic value with width '
        'greater than 64 when having different width and max constraint.', () {
      final maxValBigInt = BigInt.parse('179289266005644583');
      final maxValBigIntlv =
          LogicValue.ofBigInt(maxValBigInt, maxValBigInt.bitLength);
      const maxInt = 30;

      for (var i = INT_BITS + 1; i <= 500; i++) {
        final lvRand = Random(5).nextLogicValue(width: i);
        final lvRandMax = Random(5).nextLogicValue(width: i, max: maxValBigInt);

        final randMaxInt = Random(5).nextLogicValue(width: i, max: maxInt);
        expect(randMaxInt.toBigInt(), lessThan(BigInt.from(maxInt)));

        expect(lvRand.toBigInt(), isA<BigInt>());
        expect(lvRandMax.toBigInt(), lessThan(maxValBigIntlv.toBigInt()));
      }
    });
  });

  group('Comparable LogicValue', () {
    test('positive - int', () {
      final a = LogicValue.ofInt(3, 8);
      final b = LogicValue.ofInt(0, 8);
      final c = LogicValue.ofInt(1, 8);
      final d = LogicValue.ofInt(2, 8);
      final e = LogicValue.ofInt(23, 8);
      final f = LogicValue.ofInt(44, 8);
      final g = LogicValue.ofInt(2, 8);
      final h = LogicValue.ofInt(9, 8);

      final values = <LogicValue>[a, b, c, d, e, f, g, h];

      final expected = List<int>.filled(values.length, 0);

      for (var i = 0; i < values.length; i++) {
        expected[i] = values[i].toInt();
      }

      values.sort();
      expected.sort();
      for (var i = 0; i < values.length; i++) {
        expect(values[i].toInt(), expected[i]);
      }
    });

    test('unsigned values - int 64 bits', () {
      final a = LogicValue.ofInt(3, INT_BITS);
      final b = LogicValue.ofInt(0, INT_BITS);
      final c = LogicValue.ofInt(1, INT_BITS);
      final d = LogicValue.ofInt(2, INT_BITS);
      final e = LogicValue.ofInt(23, INT_BITS);
      final f = LogicValue.ofInt(-127, INT_BITS);
      final g = LogicValue.ofInt(-128, INT_BITS);
      final h = LogicValue.ofInt(-1, INT_BITS);

      final values = <LogicValue>[a, b, c, d, e, f, g, h];

      final expected = List<BigInt>.filled(values.length, BigInt.zero);

      for (var i = 0; i < values.length; i++) {
        expected[i] =
            BigInt.from(values[i].toInt()).toUnsigned(values[i].width);
      }

      values.sort();
      expected.sort();
      for (var i = 0; i < values.length; i++) {
        expect(BigInt.from(values[i].toInt()).toUnsigned(values[i].width),
            expected[i]);
      }
    });

    test('unsigned values - int 8 bits', () {
      final a = LogicValue.ofInt(3, 8);
      final b = LogicValue.ofInt(0, 8);
      final c = LogicValue.ofInt(1, 8);
      final d = LogicValue.ofInt(2, 8);
      final e = LogicValue.ofInt(23, 8);
      final f = LogicValue.ofInt(-127, 8);
      final g = LogicValue.ofInt(-128, 8);
      final h = LogicValue.ofInt(-1, 8);

      final values = <LogicValue>[a, b, c, d, e, f, g, h];

      final expected = List<BigInt>.filled(values.length, BigInt.zero);

      for (var i = 0; i < values.length; i++) {
        expected[i] =
            BigInt.from(values[i].toInt()).toUnsigned(values[i].width);
      }

      values.sort();
      expected.sort();

      for (var i = 0; i < values.length; i++) {
        expect(BigInt.from(values[i].toInt()).toUnsigned(values[i].width),
            expected[i]);
      }
    });

    test('unsigned BigInt & int', () {
      final a = LogicValue.ofBigInt(BigInt.parse('3'), INT_BITS);
      final b = LogicValue.ofBigInt(BigInt.zero, INT_BITS);
      final c = LogicValue.ofBigInt(BigInt.from(-1), INT_BITS);
      final d = LogicValue.ofBigInt(BigInt.one, INT_BITS);
      final e = LogicValue.ofBigInt(
          BigInt.parse('-0x3${'f' * (INT_BITS ~/ 4 - 1)}'), INT_BITS);
      final f = LogicValue.ofBigInt(
          BigInt.parse('-0x8${'0' * (INT_BITS ~/ 4 - 1)}'), INT_BITS);
      final g = LogicValue.ofBigInt(
          BigInt.parse('-0x7${'f' * (INT_BITS ~/ 4 - 1)}'), INT_BITS);
      final h = LogicValue.ofInt(-1, INT_BITS);

      final values = <LogicValue>[a, b, c, d, e, f, g, h];

      final expected = List<BigInt>.filled(values.length, BigInt.zero);
      for (var i = 0; i < values.length; i++) {
        expected[i] =
            BigInt.from(values[i].toInt()).toUnsigned(values[i].width);
      }

      values.sort();
      expected.sort();

      for (var i = 0; i < values.length; i++) {
        expect(BigInt.from(values[i].toInt()).toUnsigned(values[i].width),
            expected[i]);
      }
    });

    test('compare interpretable neg int-width numbers', () {
      final allfs = LogicValue.ofInt(0xffffffff, 32);
      final an8and0s = LogicValue.ofInt(0x80000000, 32);

      expect(allfs > an8and0s, LogicValue.one);
    });

    test('unsigned BigInt', () {
      final a = LogicValue.ofBigInt(BigInt.parse('3'), 128);
      final b = LogicValue.ofBigInt(BigInt.zero, 128);
      final c = LogicValue.ofBigInt(BigInt.from(-1), 128);
      final d = LogicValue.ofBigInt(BigInt.one, 128);
      final e = LogicValue.ofBigInt(
          BigInt.parse('340282366920938463463374607431768211455'), 128);
      final f = LogicValue.ofBigInt(
          BigInt.parse('-170141183460469231731687303715884105727'), 128);
      final g = LogicValue.ofBigInt(
          BigInt.parse('-170141183460469231731687303715884105728'), 128);
      final h = LogicValue.ofBigInt(BigInt.one, 128);

      final values = <LogicValue>[a, b, c, d, e, f, g, h];

      final expected = List<BigInt>.filled(values.length, BigInt.zero);

      for (var i = 0; i < values.length; i++) {
        expected[i] = values[i].toBigInt().toUnsigned(values[i].width);
      }

      values.sort();
      expected.sort();
      for (var i = 0; i < values.length; i++) {
        expect(values[i].toBigInt().toUnsigned(values[i].width), expected[i]);
      }
    });

    test('Exceptions', () {
      final a64 = LogicValue.ofBigInt(BigInt.parse('3'), 64);
      final a128 = LogicValue.ofBigInt(BigInt.parse('3'), 128);
      final b64 = LogicValue.ofBigInt(BigInt.zero, 64);
      final c64 = LogicValue.ofBigInt(BigInt.from(-1), 64);
      final d64 = LogicValue.ofBigInt(BigInt.one, 64);
      final e64 = LogicValue.ofInt(23, 64);
      final e8 = LogicValue.ofInt(23, 8);
      final f64 = LogicValue.ofInt(-3, 64);
      final g64 = LogicValue.ofInt(-2, 64);
      final h64 = LogicValue.ofInt(-1, 64);
      final invalidLogicX = LogicValue.filled(8, LogicValue.x);
      final invalidLogicZ = LogicValue.filled(8, LogicValue.z);

      <LogicValue>[a64, b64, c64, d64, e64, f64, g64, h64].sort();

      final excBigIntWidth = <LogicValue>[a64, b64, a128];
      final excIntWidth = <LogicValue>[e64, e8, f64];

      expect(excBigIntWidth.sort, throwsA(isA<ValueWidthMismatchException>()));
      expect(excIntWidth.sort, throwsA(isA<ValueWidthMismatchException>()));

      expect(<LogicValue>[e8, invalidLogicX].sort,
          throwsA(isA<InvalidValueOperationException>()));
      expect(<LogicValue>[e8, invalidLogicZ].sort,
          throwsA(isA<InvalidValueOperationException>()));
    });
  });

  test('BigInt toIntUnsigned extension', () {
    expect(BigInt.parse('0xf${'0' * 30}').toIntUnsigned(INT_BITS), 0);
    expect(BigInt.parse('0xf${'0' * 30}').toIntUnsigned(INT_BITS - 1), 0);

    expect(BigInt.parse('0x1f${'0' * 30}').toIntUnsigned(INT_BITS), 0);
    expect(BigInt.parse('0x1f${'0' * 30}').toIntUnsigned(INT_BITS - 1), 0);

    expect(BigInt.parse('0x${'5' * 30}').toIntUnsigned(INT_BITS),
        repeatedInt(0x5, 4, INT_BITS ~/ 4));
    expect(BigInt.parse('0x${'5' * 30}').toIntUnsigned(INT_BITS - 1),
        repeatedInt(0x5, 4, INT_BITS ~/ 4));

    expect(BigInt.parse('0x${'a' * 30}').toIntUnsigned(INT_BITS),
        repeatedInt(0xa, 4, INT_BITS ~/ 4));
    expect(BigInt.parse('0x${'a' * 30}').toIntUnsigned(INT_BITS - 4),
        repeatedInt(0xa, 4, INT_BITS ~/ 4 - 1));
  });

  test('BigInt toIntUnsigned Width Exception', () {
    expect(() => BigInt.from(1).toIntUnsigned(100), throwsA(isA<Exception>()));
  });

  test('one shift left by', () {
    expect(oneSllBy(0), 1);
    expect(oneSllBy(1), 2);
    expect(oneSllBy(2), 4);
    expect(oneSllBy(31), 0x80000000);
    expect(oneSllBy(32), 0x100000000);
    expect(oneSllBy(52), 0x10000000000000);
  });

  test('precision adjustment handled for all widths', () {
    for (var i = 1; i < 100; i++) {
      expect(
          LogicValue.of('${'1' * i}0'),
          [
            LogicValue.ofBigInt(BigInt.parse('1' * i, radix: 2), i),
            LogicValue.zero
          ].swizzle());
    }
  });

  group('RadixString', () {
    test('radixString roundTrip', () {
      final lv = LogicValue.ofBigInt(BigInt.from(737481838713847), 61);
      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
      }
    });

    test('radixString roundTrip with leading zeros', () {
      final lv = LogicValue.ofBigInt(BigInt.from(737481838713847), 61);
      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(
                lv.toRadixString(radix: i, leadingZeros: true)),
            equals(lv));
      }
    });

    test('radixString roundTrip zero corner case', () {
      final lv = LogicValue.ofBigInt(BigInt.from(0), 61);
      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
        expect(
            LogicValue.ofRadixString(
                lv.toRadixString(radix: i, leadingZeros: true)),
            equals(lv));
      }
    });

    test('radixString binary expansion', () {
      final lv = LogicValue.ofRadixString("12'b10z111011z00");
      expect(lv.toRadixString(radix: 16), equals("12'h<10z1>d<1z00>"));
      for (final i in [2, 4, 8, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
      }
    });

    test('radixString leading zero', () {
      final lv = LogicValue.ofRadixString("10'b00_0010_0111");
      expect(lv.toRadixString(), equals("10'b10_0111"));
      expect(lv.toRadixString(leadingZeros: true), equals("10'b00_0010_0111"));
      expect(lv.toRadixString(radix: 4), equals("10'q213"));
      expect(lv.toRadixString(radix: 8), equals("10'o47"));
      expect(lv.toRadixString(radix: 10), equals("10'd39"));
      expect(
          lv.toRadixString(radix: 10, leadingZeros: true), equals("10'd0039"));
      expect(lv.toRadixString(radix: 16), equals("10'h27"));
      expect(
          lv.toRadixString(radix: 16, leadingZeros: true), equals("10'h027"));
      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
      }
    });

    test('radixString round trip with alternate separation character', () {
      final lv = LogicValue.ofRadixString("10'b00.0010.0111", sepChar: '.');

      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i, sepChar: '.'),
                sepChar: '.'),
            equals(lv));
      }
      try {
        lv.toRadixString(sepChar: 'q');
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConversionException>());
      }
      try {
        lv.toRadixString(radix: 14);
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConversionException>());
      }
    });

    test('radixString space separators', () {
      final lv = LogicValue.ofRadixString("10'b10 0010 0111", sepChar: ' ');
      expect(lv.toInt(), equals(551));
    });

    test('radixString bad input', () {
      try {
        LogicValue.ofRadixString('something');
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConstructionException>());
      }
    });
    test('radixString bad input with fake length', () {
      try {
        LogicValue.ofRadixString("10'bsomething");
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConstructionException>());
      }
    });

    test('radixString bad separator', () {
      try {
        LogicValue.ofRadixString("10'b10 0010_0111");
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConstructionException>());
      }
    });

    test('radixString illegal separator', () {
      try {
        LogicValue.ofRadixString("10'b10q0010q0111", sepChar: 'q');
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConstructionException>());
      }
    });

    test('radixString bad length', () {
      try {
        LogicValue.ofRadixString("10'b10_0010_0111_0001");
        fail('Should throw a LogicValueConstructionException');
      } on Exception catch (e) {
        expect(e, isA<LogicValueConstructionException>());
      }
    });

    test('radixString shortest possible length', () {
      final lv = LogicValue.ofRadixString("10'b");
      expect(lv, equals(LogicValue.ofInt(0, 10)));
    });

    test('radixString leading Z', () {
      final lv = LogicValue.ofRadixString("10'bzz_zzz1_1011");
      expect(lv.toRadixString(), equals("10'bzz_zzz1_1011"));
      expect(lv.toRadixString(radix: 4), equals("10'qZZ<z1>23"));
      expect(lv.toRadixString(radix: 8), equals("10'oZZ<z11>3"));
      expect(lv.toRadixString(radix: 16), equals("10'hZ<zzz1>b"));
      for (final i in [2, 4, 8, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
      }
    });

    test('radixString decimal case', () {
      {
        final lv = LogicValue.ofRadixString("12'bzz_zzz1_1011");
        final ds = lv.toRadixString(radix: 10);
        final dlv = LogicValue.ofRadixString(ds);
        final ds2 = dlv.toRadixString(radix: 10);
        expect(ds, equals(ds2));
        expect(ds, equals("12'dZZZ"));
      }
      {
        final lv = LogicValue.ofRadixString("12'bzz_zzx1_1011");
        final ds = lv.toRadixString(radix: 10);
        final dlv = LogicValue.ofRadixString(ds);
        final ds2 = dlv.toRadixString(radix: 10);
        expect(ds, equals(ds2));
        expect(ds, equals("12'dXXX"));
      }
    });

    test('radixString small leading radix character', () {
      final lv = LogicValue.ofRadixString("10'b10_1010_0111");
      expect(lv.toRadixString(radix: 4), equals("10'q2_2213"));
      expect(lv.toRadixString(radix: 8), equals("10'o1247"));
      expect(lv.toRadixString(radix: 10), equals("10'd679"));
      expect(lv.toRadixString(radix: 16), equals("10'h2a7"));
      for (final i in [2, 4, 8, 10, 16]) {
        expect(
            LogicValue.ofRadixString(lv.toRadixString(radix: i)), equals(lv));
      }
    });

    test('radixString: slide set bits along entire word', () {
      final random = Random(5);

      for (var width = 15; width < 23; width++) {
        final inL = Logic(width: width);
        for (var setWidth = 1; setWidth < 12; setWidth++) {
          for (var iterations = 0; iterations < 10; iterations++) {
            final ii = random.nextInt((1 << (setWidth + 1)) - 1);
            for (var pos = 0; pos < inL.width - setWidth; pos++) {
              final l = Logic(width: width);
              l <= inL.withSet(pos, Const(ii, width: setWidth));
              final lv = l.value;
              for (final i in [2, 4, 8, 16]) {
                expect(LogicValue.ofRadixString(lv.toRadixString(radix: i)),
                    equals(lv));
              }
            }
          }
        }
      }
    });
  });
}
