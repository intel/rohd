// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_width_test.dart
// Unit tests for width issues (64-bit boundary) in [LogicValue].
//
// 2023 September 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

void main() {
  test('crash compare', () {
    final input = Const(BigInt.from(2).pow(128), width: 129);
    final output = Logic();
    Combinational([
      If.block([
        Iff(input.getRange(0, 128) > BigInt.from(0),
            [output < Const(1, width: 1)]),
        Else([output < Const(0, width: 1)]),
      ])
    ]);
  });

  test('bad compare', () {
    const i = 64;
    final input = Const(BigInt.from(1) << (i - 1), width: i);
    final output = Logic();
    Combinational([
      If.block([
        Iff(input > BigInt.from(0), [output < Const(1, width: 1)]),
        Else([output < Const(0, width: 1)]),
      ])
    ]);
    final b = ~input.eq(0);
    expect(output.value, equals(b.value));
  });

  test('big value test', () {
    expect(
        LogicValue.ofBigInt(BigInt.zero, 128) +
            LogicValue.ofBigInt(BigInt.zero, 128),
        LogicValue.ofInt(0, 128));
  });

  test('mod3 sizes', () {
    expect((LogicValue.ofInt(-5, 64) % 3).toInt(),
        (LogicValue.ofInt(-5, 80) % 3).toInt());
  });

  test('compare two positive int-width numbers', () {
    expect(LogicValue.ofInt(6, INT_BITS) < LogicValue.ofInt(7, INT_BITS),
        LogicValue.one);
  });

  group('values test', () {
    for (var len = INT_BITS - 2; len <= INT_BITS + 4; len++) {
      final sslv = LogicValue.ofInt(4, len); // small Int hold Big
      final bslv = LogicValue.ofInt(-0xFFFF, len); // 18446744073709486081
      final fslv = LogicValue.ofInt(-2, len); // 18446744073709551614

      final sblv = LogicValue.ofBigInt(BigInt.from(4), len);
      final bblv = LogicValue.ofBigInt(BigInt.from(-0xFFFF), len);
      final fblv = LogicValue.ofBigInt(BigInt.from(-2), len);

      test('small Int storage len=$len', () {
        expect(sslv < bslv, LogicValue.one);
        expect(bslv < sslv, LogicValue.zero);
        expect(sslv > bslv, LogicValue.zero);
        expect(bslv > sslv, LogicValue.one);

        expect(sslv < fslv, LogicValue.one);
        expect(fslv < sslv, LogicValue.zero);
        expect(sslv > fslv, LogicValue.zero);
        expect(fslv > sslv, LogicValue.one);

        expect(bslv < fslv, LogicValue.one);
        expect(fslv < bslv, LogicValue.zero);
        expect(bslv > fslv, LogicValue.zero);
        expect(fslv > bslv, LogicValue.one);
      });

      test('big Int storage len=$len', () {
        expect(sblv < bblv, LogicValue.one);
        expect(bblv < sblv, LogicValue.zero);
        expect(sblv > bblv, LogicValue.zero);
        expect(bblv > sblv, LogicValue.one);

        expect(sblv < fblv, LogicValue.one);
        expect(fblv < sblv, LogicValue.zero);
        expect(sblv > fblv, LogicValue.zero);
        expect(fblv > sblv, LogicValue.one);

        expect(bblv < fblv, LogicValue.one);
        expect(fblv < bblv, LogicValue.zero);
        expect(bblv > fblv, LogicValue.zero);
        expect(fblv > bblv, LogicValue.one);
      });

      test('cross compare len=$len', () {
        if (len <= INT_BITS) {
          expect(bslv.eq(bblv), LogicValue.one);
        } else {
          expect(bslv < bblv, LogicValue.one);
        }
      });

      test('big math len=$len', () {
        expect(sblv + fblv, LogicValue.ofInt(2, len));
        expect(sblv - fblv, LogicValue.ofInt(6, len));
        expect(fblv - sblv, LogicValue.ofBigInt(BigInt.from(-6), len));

        expect(sblv * fblv, LogicValue.ofBigInt(BigInt.from(-8), len));

        expect(sblv + fblv, LogicValue.ofBigInt(BigInt.from(2), len));
        expect(sblv - fblv, LogicValue.ofBigInt(BigInt.from(6), len));
        expect(fblv - sblv, LogicValue.ofBigInt(BigInt.from(-6), len));

        expect(fblv * sblv, LogicValue.ofBigInt(BigInt.from(-8), len));
      });

      test('division test len=$len', () {
        final negsfour = LogicValue.ofInt(-4, len);
        final negbfour = LogicValue.ofBigInt(BigInt.from(-4), len);
        final two = LogicValue.ofBigInt(BigInt.from(2), len);
        expect(negsfour / two, LogicValue.ofInt(-4, len) >>> 1);
        expect(negbfour / two, LogicValue.ofBigInt(BigInt.from(-4), len) >>> 1);
      });

      test('modulo test len=$len', () {
        final negsfive = LogicValue.ofInt(-5, len);
        final negbfive = LogicValue.ofBigInt(BigInt.from(-5), len);
        final two = LogicValue.ofBigInt(BigInt.from(2), len);
        expect(negsfive % two, LogicValue.ofInt(1, len));
        expect(negbfive % two, LogicValue.ofBigInt(BigInt.from(1), len));
      });

      test('clog test len=$len', () {
        final negnum = LogicValue.ofBigInt(-BigInt.one, len);
        expect(negnum.clog2(), LogicValue.ofInt(len, len));
        for (final l in [1, 2, 3]) {
          expect((negnum >>> l).clog2(), LogicValue.ofInt(len - l, len));
        }
        for (final l in [len - 5, len - 4, len - 3, len - 2]) {
          final bignum = LogicValue.ofBigInt(BigInt.from(1) << l, len);
          expect(bignum.clog2(), LogicValue.ofInt(l, len));
          if (len < INT_BITS) {
            final smallnum = LogicValue.ofInt(oneSllBy(l), len);
            expect(smallnum.clog2(), LogicValue.ofInt(l, len));
          }
        }
        for (final l in [len - 5, len - 4, len - 3]) {
          final bignum = LogicValue.ofBigInt(BigInt.from(2) << l, len);
          expect(bignum.clog2().toBigInt(), BigInt.from(l + 1));
          if (len < INT_BITS) {
            final smallnum = LogicValue.ofInt(2 << l, len);
            expect(smallnum.clog2(), LogicValue.ofInt(l + 1, len));
          }
        }
        for (final l in [len - 5, len - 4, len - 3]) {
          final bignum = LogicValue.ofBigInt(BigInt.from(3) << l, len);
          expect(bignum.clog2(), LogicValue.ofInt(l + 2, len));
          if (len < INT_BITS) {
            final smallnum = LogicValue.ofInt(3 << l, len);
            expect(smallnum.clog2(), LogicValue.ofInt(l + 2, len));
          }
        }
      });
    }
  });
}
