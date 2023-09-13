import 'package:rohd/rohd.dart';
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
  group('values test', () {
    for (final len in [63, 64, 65]) {
      final sslv = LogicValue.ofInt(3, len); // small Int hold Big
      final bslv = LogicValue.ofInt(-0xFFFF, len); // 18446744073709486081
      final fslv = LogicValue.ofInt(-2, len); // 18446744073709551614

      final sblv = LogicValue.ofBigInt(BigInt.from(3), len);
      final bblv = LogicValue.ofBigInt(BigInt.from(-0xFFFF), len);
      final fblv = LogicValue.ofBigInt(BigInt.from(-2), len);

      test('small Int storage', () {
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
      test('big Int storage', () {
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
    }
  });
}
