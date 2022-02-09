/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_values_test.dart
/// Tests for LogicValues
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

// All logicvalues to support trying all possiblities
const allLv = [LogicValue.zero, LogicValue.one, LogicValue.x, LogicValue.z];

// shorten some names to make tests read better
final lv = LogicValues.ofString;
LogicValues large(LogicValue lv) => LogicValues.filled(100, lv);

void main() {
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
      expect(lv('01xz') & LogicValues.filled(4, LogicValue.zero),
          equals(LogicValues.filled(4, LogicValue.zero)));
    });
  });

  group('LogicValues Misc', () {
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
      expect(LogicValues.ofBool(true), equals(LogicValues.ofString('1')));
      expect(LogicValues.ofBool(false), equals(LogicValues.ofString('0')));
    });
  });

  group('LogicValue', () {
    test('factory and to methods', () {
      expect(LogicValue.one.toString(), equals('1'));
      expect(LogicValue.zero.toString(), equals('0'));
      expect(LogicValue.x.toString(), equals('x'));
      expect(LogicValue.z.toString(), equals('z'));
      expect(LogicValue.one.toBool(), equals(true));
      expect(LogicValue.zero.toBool(), equals(false));
      expect(() => LogicValue.x.toBool(), throwsA(isA<Exception>()));
      expect(() => LogicValue.z.toBool(), throwsA(isA<Exception>()));
      expect(LogicValue.one.toInt(), equals(1));
      expect(LogicValue.zero.toInt(), equals(0));
      expect(() => LogicValue.x.toInt(), throwsA(isA<Exception>()));
      expect(() => LogicValue.z.toInt(), throwsA(isA<Exception>()));
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
      expect(
          () => LogicValue.isPosedge(LogicValue.x, LogicValue.one,
              ignoreInvalid: false),
          throwsA(isA<Exception>()));
      expect(
          () => LogicValue.isPosedge(LogicValue.one, LogicValue.z,
              ignoreInvalid: false),
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
      expect(
          () => LogicValue.isNegedge(LogicValue.x, LogicValue.one,
              ignoreInvalid: false),
          throwsA(isA<Exception>()));
      expect(
          () => LogicValue.isNegedge(LogicValue.one, LogicValue.z,
              ignoreInvalid: false),
          throwsA(isA<Exception>()));
    });
  });

  group('two input bitwise', () {
    test('and2', () {
      expect(
          // test all possible combinations (and fromString)
          LogicValues.ofString('00001111xxxxzzzz') &
              LogicValues.ofString('01xz01xz01xz01xz'),
          equals(LogicValues.ofString('000001xx0xxx0xxx')));
      expect(
          // test filled
          LogicValues.filled(100, LogicValue.zero) &
              LogicValues.filled(100, LogicValue.one),
          equals(LogicValues.filled(100, LogicValue.zero)));
      expect(
          // test length mismatch
          () => LogicValues.ofString('0') & LogicValues.ofString('01'),
          throwsA(isA<Exception>()));
    });

    test('or2', () {
      expect(
          // test all possible combinations
          LogicValues.ofString('00001111xxxxzzzz') |
              LogicValues.ofString('01xz01xz01xz01xz'),
          equals(LogicValues.ofString('01xx1111x1xxx1xx')));
      expect(
          // test fromInt
          LogicValues.ofInt(1, 32) | LogicValues.ofInt(0, 32),
          equals(LogicValues.ofInt(1, 32)));
      expect(
          // test fromBigInt - success
          LogicValues.ofBigInt(BigInt.one, 65) |
              LogicValues.ofBigInt(BigInt.zero, 65),
          equals(LogicValues.ofBigInt(BigInt.one, 65)));
      expect(
          // test fromBigInt
          LogicValues.ofBigInt(BigInt.one, 32) |
              LogicValues.ofBigInt(BigInt.zero, 32),
          equals(LogicValues.ofInt(1, 32)));
    });

    test('xor2', () {
      expect(
          // test all possible combinations
          LogicValues.ofString('00001111xxxxzzzz') ^
              LogicValues.ofString('01xz01xz01xz01xz'),
          equals(LogicValues.ofString('01xx10xxxxxxxxxx')));
      expect(
          // test from Iterable
          LogicValues.of([LogicValue.one, LogicValue.zero]) ^
              LogicValues.of([LogicValue.one, LogicValue.zero]),
          equals(LogicValues.of([LogicValue.zero, LogicValue.zero])));
    });
  });
  group('unary operations (including "to")', () {
    test('toMethods', () {
      expect(
          // toString
          LogicValues.ofString('0').toString(),
          equals('1\'b0'));
      expect(
          // toList
          LogicValues.ofString('0101').toList(),
          equals([
            LogicValue.one,
            LogicValue.zero,
            LogicValue.one,
            LogicValue.zero
          ]) // NOTE: "reversed" by construction (see function definition)
          );
      expect(
          // toInt - valid
          LogicValues.ofString('111').toInt(),
          equals(7));
      expect(
          // toInt - invalid
          () => LogicValues.filled(65, LogicValue.one).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValues.filled(65, LogicValue.one).toBigInt(),
          equals(BigInt.parse('36893488147419103231')));
    });

    test('properties+indexing', () {
      expect(
          // index - LSb
          LogicValues.ofString('0101')[0],
          equals(LogicValue.one) // NOTE: index 0 refers to LSb
          );
      expect(
          // index - MSb
          LogicValues.ofString('0101')[3],
          equals(LogicValue.zero) // NOTE: index (length-1) refers to MSb
          );
      expect(
          // index - out of range
          () => LogicValues.ofString('0101')[10],
          throwsA(isA<IndexError>()));
      expect(
          // index - negative
          () => LogicValues.ofString('0101')[-1],
          throwsA(isA<IndexError>()));
      expect(
          // reversed
          LogicValues.ofString('0101').reversed,
          equals(LogicValues.ofString('1010')));
      expect(
          // getRange - good inputs
          LogicValues.ofString('0101').getRange(0, 2),
          equals(LogicValues.ofString('01')));
      expect(
          // getRange - bad inputs start < 0
          () => LogicValues.ofString('0101').getRange(-2, 1),
          throwsA(isA<Exception>()));
      expect(
          // getRange - bad inputs start > end
          () => LogicValues.ofString('0101').getRange(2, 1),
          throwsA(isA<Exception>()));
      expect(
          // getRange - bad inputs end > length-1
          () => LogicValues.ofString('0101').getRange(0, 7),
          throwsA(isA<Exception>()));
      expect(
          // isValid - valid
          LogicValues.ofString('0101').isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValues.ofString('01x1').isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValues.ofString('01z1').isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValues.ofString('zzzz').isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValues.ofString('zzz1').isFloating,
          equals(false));
    });

    test('shifts', () {
      expect(
          // sll
          LogicValues.ofString('1111') << 2,
          equals(LogicValues.ofString('1100')));
      expect(
          // sra
          LogicValues.ofString('1111') >> 2,
          equals(LogicValues.ofString('1111')));
      expect(
          // srl
          LogicValues.ofString('1111') >>> 2,
          equals(LogicValues.ofString('0011')));
    });
  });
  group('comparison operations', () {
    test('equality', () {
      expect(
          // == equal
          LogicValues.ofString('1111') == LogicValues.ofString('1111'),
          equals(true));
      expect(
          // == not equal
          LogicValues.ofString('1111') == LogicValues.ofString('1110'),
          equals(false));
      expect(
          // eq equal
          LogicValues.ofString('1111').eq(LogicValues.ofString('1111')),
          equals(LogicValue.one));
      expect(
          // eq not equal, valid
          LogicValues.ofString('1111').eq(LogicValues.ofString('1110')),
          equals(LogicValue.zero));
      expect(
          // eq not equal, invalid
          LogicValues.ofString('1111').eq(LogicValues.ofString('111x')),
          equals(LogicValue.x));
    });

    test('greater', () {
      expect(
          // >
          LogicValues.ofString('0111') > LogicValues.ofString('0110'),
          equals(LogicValue.one));
      expect(
          // not >
          LogicValues.ofString('0111') > LogicValues.ofString('0111'),
          equals(LogicValue.zero));
      expect(
          // >=
          LogicValues.ofString('0111') >= LogicValues.ofString('0111'),
          equals(LogicValue.one));
      expect(
          // not >=
          LogicValues.ofString('0110') >= LogicValues.ofString('0111'),
          equals(LogicValue.zero));
      expect(
          // x involved
          LogicValues.ofString('0110') >= LogicValues.ofString('011x'),
          equals(LogicValue.x));
      expect(
          // mismatched lengths
          () => LogicValues.ofString('0110') >= LogicValues.ofString('011000'),
          throwsA(isA<Exception>()));
    });

    test('less', () {
      expect(
          // <
          LogicValues.ofString('0111') < 8,
          equals(LogicValue.one));
      expect(
          // not <
          LogicValues.ofString('0111') < 7,
          equals(LogicValue.zero));
      expect(
          // <=
          LogicValues.ofString('0111') <= 7,
          equals(LogicValue.one));
      expect(
          // not <=
          LogicValues.ofString('0110') <= 5,
          equals(LogicValue.zero));
      expect(
          // x involved
          LogicValues.ofString('011x') <= 10,
          equals(LogicValue.x));
    });
  });
  group('arithmetic operations', () {
    test('addsub', () {
      expect(
          // + normal
          LogicValues.ofString('0001') + LogicValues.ofString('0011'),
          equals(LogicValues.ofString('0100')) // 1 + 3 = 4
          );
      expect(
          // - normal
          LogicValues.ofString('0001') - LogicValues.ofString('0001'),
          equals(LogicValues.ofString('0000')) // 1 - 1 = 0
          );
      expect(
          // + overflow
          LogicValues.ofString('1111') + LogicValues.ofString('0001'),
          equals(LogicValues.ofString('0000')));
      expect(
          // - overflow
          LogicValues.ofString('0000') - LogicValues.ofString('0001'),
          equals(LogicValues.ofString('1111')));
      expect(
          // x involved
          LogicValues.ofString('0000') + LogicValues.ofString('111x'),
          equals(LogicValues.ofString('xxxx')));
      expect(
          // length mismatch
          () => LogicValues.ofString('0000') - LogicValues.ofString('000100'),
          throwsA(isA<Exception>()));
    });
    test('muldiv', () {
      expect(
          // * normal
          LogicValues.ofString('0001') * LogicValues.ofString('0011'),
          equals(LogicValues.ofString('0011')) // 1 * 3 = 3
          );
      expect(
          // / normal
          LogicValues.ofString('0100') / LogicValues.ofString('0010'),
          equals(LogicValues.ofString('0010')) // 4 / 2 = 2
          );
      expect(
          // / truncate
          LogicValues.ofString('0100') / LogicValues.ofString('0011'),
          equals(LogicValues.ofString('0001')) // 4 / 3 = 1 (integer division)
          );
      expect(
          // div-by-0
          () => LogicValues.ofString('0100') / LogicValues.ofString('0000'),
          throwsA(isA<Exception>()));
      expect(
          // * overflow
          LogicValues.ofString('0100') * LogicValues.ofString('0100'),
          equals(LogicValues.ofString('0000')));
    });
  });

  group('not and reductions', () {
    test('not', () {
      expect(
          // not - valid
          ~LogicValues.ofString('0100'),
          equals(LogicValues.ofString('1011')));
      expect(
          // not - invalid
          ~LogicValues.ofString('zzxx'),
          equals(LogicValues.ofString('xxxx')));
    });
    test('and', () {
      expect(
          // and - valid
          LogicValues.ofString('0100').and(),
          equals(LogicValue.zero));
      expect(
          // and - valid (1's)
          LogicValues.ofString('1111').and(),
          equals(LogicValue.one));
      expect(
          // and - invalid
          LogicValues.ofString('010x').and(),
          equals(LogicValue.zero));
      expect(
          // and - invalid (1's)
          LogicValues.ofString('111z').and(),
          equals(LogicValue.x));
    });
    test('or', () {
      expect(
          // or - valid
          LogicValues.ofString('0100').or(),
          equals(LogicValue.one));
      expect(
          // or - valid (0's)
          LogicValues.ofString('0000').or(),
          equals(LogicValue.zero));
      expect(
          // or - invalid
          LogicValues.ofString('010x').or(),
          equals(LogicValue.one));
      expect(
          // or - invalid (1's)
          LogicValues.ofString('000z').or(),
          equals(LogicValue.x));
    });
    test('xor', () {
      expect(
          // xor - valid (even)
          LogicValues.ofString('1100').xor(),
          equals(LogicValue.zero));
      expect(
          // xor - valid (odd)
          LogicValues.ofString('1110').xor(),
          equals(LogicValue.one));
      expect(
          // xor - invalid
          LogicValues.ofString('010x').xor(),
          equals(LogicValue.x));
    });
  });
  group('BigLogicValues', () {
    test('overrides', () {
      expect(
          // reversed
          LogicValues.ofString('01' * 100).reversed,
          equals(LogicValues.ofString('10' * 100)));
      expect(
          // isValid - valid
          LogicValues.ofString('01' * 100).isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValues.ofString('0x' * 100).isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValues.ofString('1z' * 100).isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValues.ofString('z' * 100).isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValues.ofString('z1' * 100).isFloating,
          equals(false));
      expect(
          // toInt - always invalid
          () => LogicValues.ofString('11' * 100).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - invalid
          () => LogicValues.ofString('1x' * 100).toBigInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValues.ofString('0' * 100).toBigInt(),
          equals(BigInt.from(0)));
      expect(
          // not - valid
          ~LogicValues.ofString('0' * 100),
          equals(LogicValues.ofString('1' * 100)));
      expect(
          // not - invalid
          ~LogicValues.ofString('z1' * 100),
          equals(LogicValues.ofString('x0' * 100)));
      expect(
          // and - valid
          LogicValues.ofString('01' * 100).and(),
          equals(LogicValue.zero));
      expect(
          // and - valid (1's)
          LogicValues.ofString('1' * 100).and(),
          equals(LogicValue.one));
      expect(
          // and - invalid
          LogicValues.ofString('01x' * 100).and(),
          equals(LogicValue.zero));
      expect(
          // and - invalid (1's)
          LogicValues.ofString('111z' * 100).and(),
          equals(LogicValue.x));
      expect(
          // or - valid
          LogicValues.ofString('01' * 100).or(),
          equals(LogicValue.one));
      expect(
          // or - valid (0's)
          LogicValues.ofString('0' * 100).or(),
          equals(LogicValue.zero));
      expect(
          // or - invalid
          LogicValues.ofString('10x' * 100).or(),
          equals(LogicValue.one));
      expect(
          // or - invalid (1's)
          LogicValues.ofString('0z' * 100).or(),
          equals(LogicValue.x));
      expect(
          // xor - valid (even)
          LogicValues.ofString('1100' * 100).xor(),
          equals(LogicValue.zero));
      expect(
          // xor - valid (odd)
          LogicValues.ofString('1110' * 99).xor(),
          equals(LogicValue.one));
      expect(
          // xor - invalid
          LogicValues.ofString('010x' * 100).xor(),
          equals(LogicValue.x));
      expect(
          // fromInt with >64 bits
          LogicValues.ofInt(3, 512),
          equals(LogicValues.ofBigInt(BigInt.from(3), 512)));
    });
  });

  group('FilledLogicValues', () {
    test('overrides', () {
      expect(
          // reversed
          LogicValues.filled(100, LogicValue.one).reversed,
          equals(LogicValues.filled(100, LogicValue.one)));
      expect(
          // reversed
          LogicValues.filled(100, LogicValue.zero).reversed,
          equals(LogicValues.filled(100, LogicValue.zero)));
      expect(
          // isValid - valid
          LogicValues.filled(100, LogicValue.zero).isValid,
          equals(true));
      expect(
          // isValid - valid
          LogicValues.filled(100, LogicValue.one).isValid,
          equals(true));
      expect(
          // isValid - invalid ('x')
          LogicValues.filled(100, LogicValue.x).isValid,
          equals(false));
      expect(
          // isValid - invalid ('z')
          LogicValues.filled(100, LogicValue.z).isValid,
          equals(false));
      expect(
          // isFloating - floating
          LogicValues.filled(100, LogicValue.z).isFloating,
          equals(true));
      expect(
          // isFloating - not floating
          LogicValues.filled(100, LogicValue.one).isFloating,
          equals(false));
      expect(
          // toInt - invalid
          () => LogicValues.filled(100, LogicValue.one).toInt(),
          throwsA(isA<Exception>()));
      expect(
          // toInt - valid
          LogicValues.filled(64, LogicValue.zero).toInt(),
          equals(0));
      expect(
          // toBigInt - invalid
          () => LogicValues.filled(100, LogicValue.x).toBigInt(),
          throwsA(isA<Exception>()));
      expect(
          // toBigInt - valid
          LogicValues.filled(100, LogicValue.zero).toBigInt(),
          equals(BigInt.from(0)));
      expect(
          // not - valid
          ~LogicValues.filled(100, LogicValue.zero),
          equals(LogicValues.filled(100, LogicValue.one)));
      expect(
          // not - valid
          ~LogicValues.filled(100, LogicValue.one),
          equals(LogicValues.filled(100, LogicValue.zero)));
      expect(
          // not - invalid
          ~LogicValues.filled(100, LogicValue.z),
          equals(LogicValues.filled(100, LogicValue.x)));
      expect(
          // and - valid 0
          LogicValues.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // and - valid 1
          LogicValues.filled(100, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // and - invalid x
          LogicValues.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // and - invalid z
          LogicValues.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
      expect(
          // or - valid 0
          LogicValues.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // or - valid 1
          LogicValues.filled(100, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // or - invalid x
          LogicValues.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // or - invalid z
          LogicValues.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
      expect(
          // xor - valid 0
          LogicValues.filled(100, LogicValue.zero).and(),
          equals(LogicValue.zero));
      expect(
          // xor - valid 1
          LogicValues.filled(99, LogicValue.one).and(),
          equals(LogicValue.one));
      expect(
          // xor - invalid x
          LogicValues.filled(100, LogicValue.x).and(),
          equals(LogicValue.x));
      expect(
          // xor - invalid z
          LogicValues.filled(100, LogicValue.z).and(),
          equals(LogicValue.x));
    });
  });
}
