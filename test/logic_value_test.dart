/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_value_test.dart
/// Tests for LogicValue
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

// All logicvalues to support trying all possiblities
const allLv = [LogicValue.zero, LogicValue.one, LogicValue.x, LogicValue.z];

// shorten some names to make tests read better
const lv = LogicValue.ofString;
LogicValue large(LogicValue lv) => LogicValue.filled(100, lv);

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
      expect(LogicValue.ofString('1' * 64), equals(LogicValue.ofInt(-1, 64)));
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
              LogicValue.ofBigInt(BigInt.zero, 65),
          equals(LogicValue.ofBigInt(BigInt.one, 65)));
      expect(
          // test ofBigInt
          LogicValue.ofBigInt(BigInt.one, 32) |
              LogicValue.ofBigInt(BigInt.zero, 32),
          equals(LogicValue.ofInt(1, 32)));
    });

    test('xor2', () {
      expect(
          // test all possible combinations
          LogicValue.ofString('00001111xxxxzzzz') ^
              LogicValue.ofString('01xz01xz01xz01xz'),
          equals(LogicValue.ofString('01xx10xxxxxxxxxx')));
      expect(
          // test from Iterable
          LogicValue.of([LogicValue.one, LogicValue.zero]) ^
              LogicValue.of([LogicValue.one, LogicValue.zero]),
          equals(LogicValue.of([LogicValue.zero, LogicValue.zero])));
    });
  });

  test('LogicValue.of example', () {
    final it = [LogicValue.zero, LogicValue.x, LogicValue.ofString('01xz')];
    final lv = LogicValue.of(it);
    expect(lv.toString(), equals("6'b01xzx0"));
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
          throwsA(isA<Exception>()));
      expect(
          // getRange - same index results zero width value
          LogicValue.ofString('0101').getRange(-1, -1),
          LogicValue.ofString(''));
      expect(
          // getRange - bad inputs start > end
          () => LogicValue.ofString('0101').getRange(2, 1),
          throwsA(isA<Exception>()));
      expect(
          // getRange - bad inputs end > length-1
          () => LogicValue.ofString('0101').getRange(0, 7),
          throwsA(isA<Exception>()));
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

    test('shifts', () {
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
  });
  group('comparison operations', () {
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
          () => LogicValue.ofString('0100') % LogicValue.ofString('0000'),
          throwsA(isA<Exception>()));
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
          () => LogicValue.ofString('0100') / LogicValue.ofString('0000'),
          throwsA(isA<Exception>()));
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
      final smaller = extraWide.getRange(0, 64);
      expect(smaller.toInt(), equals(0xf0f0f0f0f0f0f0f0));
    });
    test(
        '64-bit BigInts larger than max pos int value constructing'
        ' a LogicValue is correct', () {
      final bigInt64Lv =
          LogicValue.ofBigInt(BigInt.parse('fa' * 8, radix: 16), 64);
      expect(bigInt64Lv.toInt(), equals(0xfafafafafafafafa));
    });
    test('64-bit binary negatives are converted properly with bin', () {
      expect(bin('1110' * 16), equals(0xeeeeeeeeeeeeeeee));
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
}
