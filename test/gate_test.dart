// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// gate_test.dart
// Unit tests for basic gates
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ContentionModule extends Module {
  Logic get y => output('y');
  ContentionModule() : super(name: 'contentionmodule') {
    final y = addOutput('y');
    y <= ~y;
  }
}

class GateTestModule extends Module {
  Logic get aBar => output('a_bar');
  Logic get aAndB => output('a_and_b');
  Logic get aOrB => output('a_or_b');
  Logic get aXorB => output('a_xor_b');

  GateTestModule(Logic a, Logic b) : super(name: 'gatetestmodule') {
    a = addInput('a', a);
    b = addInput('b', b);

    final aBar = addOutput('a_bar');
    final aAndB = addOutput('a_and_b');
    final aOrB = addOutput('a_or_b');
    final aXorB = addOutput('a_xor_b');

    aBar <= ~a;
    aAndB <= a & b;
    aOrB <= a | b;
    aXorB <= a ^ b;
  }
}

class UnaryGateTestModule extends Module {
  UnaryGateTestModule(Logic a) : super(name: 'ugatetestmodule') {
    a = addInput('a', a, width: a.width);

    final aAnd = addOutput('a_and');
    final aOr = addOutput('a_or');
    final aXor = addOutput('a_xor');

    aAnd <= a.and();
    aOr <= a.or();
    aXor <= a.xor();
  }
}

class Absolute extends Module {
  Absolute(Logic a) : super(name: 'absolute') {
    a = addInput('a', a, width: a.width);

    final y = addOutput('y', width: a.width);

    y <= a.abs();
  }
}

class ShiftTestModule extends Module {
  dynamic constant; // int or BigInt

  ShiftTestModule(Logic a, Logic b, {this.constant = 3})
      : super(name: 'shifttestmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aRshiftB = addOutput('a_rshift_b', width: a.width);
    final aLshiftB = addOutput('a_lshift_b', width: a.width);
    final aArshiftB = addOutput('a_arshift_b', width: a.width);

    final aRshiftConst = addOutput('a_rshift_const', width: a.width);
    final aLshiftConst = addOutput('a_lshift_const', width: a.width);
    final aArshiftConst = addOutput('a_arshift_const', width: a.width);

    aRshiftB <= a >>> b;
    aLshiftB <= a << b;
    aArshiftB <= a >> b;
    aRshiftConst <= a >>> constant;
    aLshiftConst <= a << constant;
    aArshiftConst <= a >> constant;
  }
}

class MuxWrapper extends Module {
  MuxWrapper(Logic control, Logic d0, Logic d1) : super(name: 'muxwrapper') {
    control = addInput('control', control);
    d0 = addInput('d0', d0, width: d0.width);
    d1 = addInput('d1', d1, width: d1.width);
    final y = addOutput('y', width: d0.width);

    y <= Mux(control, d1, d0).out;
  }
}

class IndexGateTestModule extends Module {
  IndexGateTestModule(Logic original, Logic index)
      : super(name: 'indexgatetestmodule') {
    original = addInput('original', original, width: original.width);
    index = addInput('index', index, width: index.width);
    final bitSet = addOutput('index_output');

    bitSet <= original[index];
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('functional', () {
    test('NotGate single bit', () async {
      final a = Logic();
      final gtm = GateTestModule(a, Logic());
      final out = gtm.aBar;
      await gtm.build();
      a.put(1);
      expect(out.value.toInt(), equals(0));
      a.put(0);
      expect(out.value.toInt(), equals(1));
    });

    test('Contention not gate', () async {
      final mod = ContentionModule();
      await mod.build();
      mod.y.put(0);
      expect(mod.y.value, equals(LogicValue.x));
    });

    test('And2Gate single bit', () async {
      final a = Logic();
      final b = Logic();
      final gtm = GateTestModule(a, b);
      final out = gtm.aAndB;
      await gtm.build();
      a.put(0);
      b.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0);
      b.put(1);
      expect(out.value.toInt(), equals(0));
      a.put(1);
      b.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(1);
      b.put(1);
      expect(out.value.toInt(), equals(1));
    });

    test('Or2Gate single bit', () async {
      final a = Logic();
      final b = Logic();
      final gtm = GateTestModule(a, b);
      final out = gtm.aOrB;
      await gtm.build();
      a.put(0);
      b.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0);
      b.put(1);
      expect(out.value.toInt(), equals(1));
      a.put(1);
      b.put(0);
      expect(out.value.toInt(), equals(1));
      a.put(1);
      b.put(1);
      expect(out.value.toInt(), equals(1));
    });

    test('Xor2Gate single bit', () async {
      final a = Logic();
      final b = Logic();
      final gtm = GateTestModule(a, b);
      final out = gtm.aXorB;
      await gtm.build();
      a.put(0);
      b.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0);
      b.put(1);
      expect(out.value.toInt(), equals(1));
      a.put(1);
      b.put(0);
      expect(out.value.toInt(), equals(1));
      a.put(1);
      b.put(1);
      expect(out.value.toInt(), equals(0));
    });
  });

  test('mux shorthand', () {
    final control = Logic();
    final d0 = Logic();
    final d1 = Logic();
    final result = mux(control, d1, d0);

    d0.put(0);
    d1.put(1);
    control.put(0);

    expect(result.value, LogicValue.zero);

    control.put(1);

    expect(result.value, LogicValue.one);
  });

  group('Cases', () {
    test('test LogicValue', () {
      final control = Logic(width: 8);
      final d0 = Logic(width: 8)..put(LogicValue.ofInt(2, 8));
      final d1 = Logic(width: 8)..put(LogicValue.ofInt(3, 8));
      final result = cases(
          control,
          {
            d0: LogicValue.ofInt(2, 8),
            d1: LogicValue.ofInt(3, 8),
          },
          width: 8);

      control.put(2);

      expect(result.value, LogicValue.ofInt(2, 8));

      control.put(3);

      expect(result.value, LogicValue.ofInt(3, 8));
    });

    test('test Int', () {
      final control = Logic(width: 4)..put(LogicValue.ofInt(2, 4));
      const d0 = 2;
      const d1 = 3;

      final result = cases(
          control,
          {
            d0: 2,
            d1: 3,
          },
          width: 4,
          defaultValue: 3);

      expect(result.value, LogicValue.ofInt(2, 4));
    });

    test('test Logic', () {
      final control = Logic();
      final d0 = Logic()..put(LogicValue.zero);
      final d1 = Logic()..put(LogicValue.one);
      final result = cases(control, {
        d0: LogicValue.zero,
        d1: LogicValue.one,
      });

      control.put(0);
      expect(result.value, LogicValue.zero);

      control.put(1);
      expect(result.value, LogicValue.one);
    });

    test('test Default', () {
      final control = Logic(width: 4);
      const d0 = 1;
      const d1 = 2;
      final result = cases(
          control,
          {
            d0: 1,
            d1: 2,
          },
          width: 4,
          defaultValue: 3);

      control.put(LogicValue.zero);
      expect(result.value, LogicValue.ofInt(3, 4));
    });

    test('test Exceptions(Int)', () {
      final control = Logic(width: 4);
      final d0 = Logic(width: 4);
      final d1 = Logic(width: 8);

      control.put(LogicValue.ofInt(2, 4));
      d0.put(LogicValue.ofInt(2, 4));
      d1.put(LogicValue.ofInt(3, 8));

      expect(() => cases(control, {d0: 2, d1: 3}, width: 4),
          throwsA(isA<SignalWidthMismatchException>()));
    });

    test('test Condition width mismatch Exception', () {
      final control = Logic();
      final d0 = Logic();
      final d1 = Logic(width: 8);

      control.put(LogicValue.zero);
      d0.put(LogicValue.zero);
      d1.put(LogicValue.ofInt(1, 8));

      expect(
          () =>
              cases(control, {d0: LogicValue.zero, d1: LogicValue.ofInt(1, 8)}),
          throwsA(isA<SignalWidthMismatchException>()));
    });

    test('test Expression width mismatch Exception for Logic', () {
      final control = Logic();
      final d0 = Logic(width: 8);
      final d1 = Logic(width: 8);

      control.put(LogicValue.one);

      expect(
          () => cases(control, {d0: Logic(width: 8), d1: Logic(width: 8)},
              width: 8),
          throwsA(isA<SignalWidthMismatchException>()));
    });

    test('test Expression width mismatch Exception for LogicValue', () {
      final control = Logic();
      final d0 = LogicValue.ofInt(0, 8);
      final d1 = LogicValue.ofInt(1, 8);

      control.put(LogicValue.one);

      expect(
          () => cases(
              control, {d0: LogicValue.ofInt(0, 8), d1: LogicValue.ofInt(1, 8)},
              width: 8),
          throwsA(isA<SignalWidthMismatchException>()));
    });

    test('test Null width Exception', () {
      final control = Logic();
      const d0 = 2;
      const d1 = 4;

      control.put(LogicValue.zero);
      expect(() => cases(control, {d0: 2, d1: 4}, defaultValue: 3),
          throwsA(isA<SignalWidthMismatchException>()));
    });
  });

  group('Const input Gate test', () {
    test('NotGate single bit Constant input', () async {
      final normalLogic = Logic();
      final const0 = Const(LogicValue.zero, width: 1);
      final constX = Const(LogicValue.x, width: 1);
      final const1 = Const(LogicValue.one, width: 1);
      normalLogic.put(LogicValue.one);

      expect(~const0, isA<Const>());
      expect((~const0).value, equals(LogicValue.one));

      expect(~constX, isA<Const>());
      expect((~constX).value, equals(LogicValue.x));

      expect(~const1, isA<Const>());
      expect((~const1).value, equals(LogicValue.zero));
    });

    test('NotGate Multi bit Constant input', () async {
      final const1 = Const(bin('1111'), width: 4);
      final const4 = Const(bin('0100'), width: 4);

      expect(~const1, isA<Const>());
      expect((~const1).value, equals(LogicValue.of(LogicValue.zero, width: 4)));

      expect(~const4, isA<Logic>());
      expect((~const4).value, equals(LogicValue.of(11, width: 4)));
    });

    test('And2Gate Single bit Constant input', () async {
      final normalLogic = Logic();
      final const0 = Const(LogicValue.zero);
      final logicX = Logic();
      final const1 = Const(LogicValue.one);
      normalLogic.put(LogicValue.one);
      logicX.put(LogicValue.x);

      expect(normalLogic & const0, isA<Const>());
      expect((normalLogic & const0).value, equals(LogicValue.zero));
      expect(logicX & const0, isA<Const>());
      expect((logicX & const0).value, equals(LogicValue.zero));
      expect(normalLogic & const1, isA<Logic>());
      expect((normalLogic & const1).value, equals(normalLogic.value));
      expect(normalLogic & logicX, isA<Logic>());
      expect((normalLogic & logicX).value, equals(LogicValue.x));
      expect(const0 & const1, isA<Const>());
    });

    test('And2Gate Multi bit Constant input', () async {
      final const1 = Const(bin('1111'), width: 4);
      final const4 = Const(bin('0100'), width: 4);
      final logic0 = Logic(width: 4)..put(LogicValue.zero);
      final logic1 = Logic(width: 4)..put(LogicValue.one);
      final logicX = Logic(width: 4)..put(LogicValue.x);

      expect(const1 & const4, isA<Const>());
      expect((const1 & const4).value, equals(LogicValue.of('0100', width: 4)));

      expect(logic0 & const1, isA<Logic>());
      expect((logic0 & const1).value, equals(LogicValue.of('0000', width: 4)));

      expect(logic1 & const1, isA<Logic>());
      expect((logic1 & const1).value, equals(LogicValue.of('0001', width: 4)));

      expect(logicX & const1, isA<Logic>());
      expect((logicX & const1).value, equals(LogicValue.of('xxxx', width: 4)));
    });

    test('OR2Gate Single bit Constant input', () async {
      final a = Logic();
      final b = Const(LogicValue.zero, width: 1);
      final c = Const(LogicValue.x, width: 1);
      final d = Const(LogicValue.one, width: 1);
      final z = Const('11111', width: 5);
      final y = Const(LogicValue.of('11x01', width: 5));
      a.put(LogicValue.one);

      expect(a | b, isA<Logic>());
      expect((a | b).value, equals(a.value));

      expect(a | c, isA<Logic>());
      expect((a | c).value, equals(LogicValue.one));

      expect(a | d, isA<Logic>());
      expect((a | d).value, equals(LogicValue.one));

      expect(y | z, isA<Logic>());
      expect((y | z).value, equals(LogicValue.of('11111', width: 5)));
    });

    test('OR2Gate Multi bit Constant input', () async {
      final a = Const(LogicValue.of(LogicValue.zero, width: 4));
      final b = Const(bin('1111'), width: 4);
      final c = Const(bin('0100'), width: 4);

      expect(a | c, isA<Logic>());
      expect((a | c).value, equals(c.value));

      expect(b | c, isA<Const>());
      expect((b | c).value, equals(LogicValue.filled(4, LogicValue.one)));
    });
  });

  group('simcompare', () {
    test('NotGate single bit', () async {
      final gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 1}, {'a_bar': 0}),
        Vector({'a': 0}, {'a_bar': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      SimCompare.checkIverilogVector(gtm, vectors);
    });

    test('unary and', () async {
      final gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      final vectors = [
        Vector({'a': bin('0000')}, {'a_and': 0}),
        Vector({'a': bin('1010')}, {'a_and': 0}),
        Vector({'a': bin('1111')}, {'a_and': 1}),
        Vector({'a': bin('0001')}, {'a_and': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('unary or', () async {
      final gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      final vectors = [
        Vector({'a': bin('0000')}, {'a_or': 0}),
        Vector({'a': bin('1010')}, {'a_or': 1}),
        Vector({'a': bin('1111')}, {'a_or': 1}),
        Vector({'a': bin('0001')}, {'a_or': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('unary xor', () async {
      final gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      final vectors = [
        Vector({'a': bin('0000')}, {'a_xor': 0}),
        Vector({'a': bin('1010')}, {'a_xor': 0}),
        Vector({'a': bin('1111')}, {'a_xor': 0}),
        Vector({'a': bin('0001')}, {'a_xor': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Mux single bit', () async {
      final mod = MuxWrapper(Logic(), Logic(), Logic());
      await mod.build();
      final vectors = [
        Vector({'control': 1, 'd0': 0, 'd1': 1}, {'y': 1}),
        Vector({'control': 0, 'd0': 0, 'd1': 1}, {'y': 0}),
        Vector({'control': 0, 'd0': 1, 'd1': 1}, {'y': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('absolute', () async {
      final mod = Absolute(Logic(width: 4));
      await mod.build();
      final vectors = [
        Vector({'a': bin('1111')}, {'y': bin('0001')}),
        Vector({'a': bin('0110')}, {'y': bin('0110')}),
        Vector({'a': bin('0010')}, {'y': bin('0010')}),
        Vector({'a': bin('1011')}, {'y': bin('0101')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

    test('Mux bus', () async {
      final mod = MuxWrapper(Logic(), Logic(width: 8), Logic(width: 8));
      await mod.build();
      final vector1 = [
        Vector({'control': 1, 'd0': 12, 'd1': 15}, {'y': 15}),
        Vector({'control': 0, 'd0': 18, 'd1': 7}, {'y': 18}),
        Vector({'control': 0, 'd0': 3, 'd1': 6}, {'y': 3}),
        Vector({'control': 0, 'd0': 10, 'd1': LogicValue.z}, {'y': 10}),
        Vector({'control': 1, 'd0': LogicValue.z, 'd1': 6}, {'y': 6}),
      ];

      final vector2 = [
        Vector(
            {'control': 1, 'd0': 6, 'd1': LogicValue.z}, {'y': LogicValue.x}),
        Vector(
            {'control': LogicValue.z, 'd0': 10, 'd1': 6}, {'y': LogicValue.x}),
        Vector(
            {'control': 0, 'd0': LogicValue.z, 'd1': 10}, {'y': LogicValue.x}),
      ];

      await SimCompare.checkFunctionalVector(mod, vector1 + vector2);
      final simResult = SimCompare.iverilogVector(mod, vector1);
      expect(simResult, equals(true));
    });

    group('shift', () {
      test('lshift logic', () async {
        final gtm = ShiftTestModule(Logic(width: 3), Logic(width: 8));
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010'), 'b': 0}, {'a_lshift_b': bin('010')}),
          Vector({'a': bin('010'), 'b': 1}, {'a_lshift_b': bin('100')}),
          Vector({'a': bin('010'), 'b': 2}, {'a_lshift_b': bin('000')}),
          Vector({'a': bin('010'), 'b': 6}, {'a_lshift_b': bin('000')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('rshift logic', () async {
        final gtm = ShiftTestModule(Logic(width: 3), Logic(width: 8));
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010'), 'b': 0}, {'a_rshift_b': bin('010')}),
          Vector({'a': bin('010'), 'b': 1}, {'a_rshift_b': bin('001')}),
          Vector({'a': bin('010'), 'b': 2}, {'a_rshift_b': bin('000')}),
          Vector({'a': bin('010'), 'b': 6}, {'a_rshift_b': bin('000')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('arshift logic', () async {
        final gtm = ShiftTestModule(Logic(width: 3), Logic(width: 8));
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010'), 'b': 0}, {'a_arshift_b': bin('010')}),
          Vector({'a': bin('010'), 'b': 1}, {'a_arshift_b': bin('001')}),
          Vector({'a': bin('010'), 'b': 2}, {'a_arshift_b': bin('000')}),
          Vector({'a': bin('010'), 'b': 6}, {'a_arshift_b': bin('000')}),
          Vector({'a': bin('110'), 'b': 0}, {'a_arshift_b': bin('110')}),
          Vector({'a': bin('110'), 'b': 6}, {'a_arshift_b': bin('111')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('lshift int', () async {
        final gtm =
            ShiftTestModule(Logic(width: 3), Logic(width: 8), constant: 1);
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010')}, {'a_lshift_const': bin('100')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('rshift int', () async {
        final gtm =
            ShiftTestModule(Logic(width: 3), Logic(width: 8), constant: 1);
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010')}, {'a_rshift_const': bin('001')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('arshift int', () async {
        final gtm =
            ShiftTestModule(Logic(width: 3), Logic(width: 8), constant: 1);
        await gtm.build();
        final vectors = [
          Vector({'a': bin('010')}, {'a_arshift_const': bin('001')}),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('shift by const zero', () async {
        final gtm =
            ShiftTestModule(Logic(width: 3), Logic(width: 8), constant: 0);
        await gtm.build();
        final sv = gtm.generateSynth();

        expect(sv, isNot(contains("0'h0")));

        final vectors = [
          Vector({
            'a': bin('010')
          }, {
            'a_arshift_const': bin('010'),
            'a_lshift_const': bin('010'),
            'a_rshift_const': bin('010')
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('large logic shifted by small bus', () async {
        final gtm =
            ShiftTestModule(Logic(width: 200), Logic(width: 60), constant: 70);
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 100,
            'b': 70
          }, {
            'a_lshift_const': BigInt.one << 170,
            'a_rshift_const': BigInt.one << 30,
            'a_arshift_const': BigInt.one << 30,
            'a_lshift_b': BigInt.one << 170,
            'a_rshift_b': BigInt.one << 30,
            'a_arshift_b': BigInt.one << 30,
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('large logic shifted by large bus', () async {
        final gtm = ShiftTestModule(Logic(width: 200), Logic(width: 200),
            constant: BigInt.from(70));
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 100,
            'b': 70
          }, {
            'a_lshift_const': BigInt.one << 170,
            'a_rshift_const': BigInt.one << 30,
            'a_arshift_const': BigInt.one << 30,
            'a_lshift_b': BigInt.one << 170,
            'a_rshift_b': BigInt.one << 30,
            'a_arshift_b': BigInt.one << 30,
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('small logic shifted by large bus', () async {
        final gtm =
            ShiftTestModule(Logic(width: 40), Logic(width: 200), constant: 10);
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 20,
            'b': 10
          }, {
            'a_lshift_const': BigInt.one << 30,
            'a_rshift_const': BigInt.one << 10,
            'a_arshift_const': BigInt.one << 10,
            'a_lshift_b': BigInt.one << 30,
            'a_rshift_b': BigInt.one << 10,
            'a_arshift_b': BigInt.one << 10,
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('large logic shifted by huge value on large bus', () async {
        final gtm = ShiftTestModule(Logic(width: 200), Logic(width: 200),
            constant: BigInt.one << 100);
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 199 | BigInt.one << 100,
            'b': BigInt.one << 100
          }, {
            'a_lshift_const': 0,
            'a_rshift_const': 0,
            'a_arshift_const': LogicValue.filled(200, LogicValue.one),
            'a_lshift_b': 0,
            'a_rshift_b': 0,
            'a_arshift_b': LogicValue.filled(200, LogicValue.one),
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('small logic shifted by huge value on large bus', () async {
        final gtm = ShiftTestModule(Logic(width: 40), Logic(width: 200),
            constant: BigInt.one << 100);
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 200 | BigInt.one << 100,
            'b': BigInt.one << 100
          }, {
            'a_lshift_const': 0,
            'a_rshift_const': 0,
            'a_arshift_const': LogicValue.filled(40, LogicValue.zero),
            'a_lshift_b': 0,
            'a_rshift_b': 0,
            'a_arshift_b': LogicValue.filled(40, LogicValue.zero),
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });

      test('very small logic shifted by huge value on large bus', () async {
        final gtm = ShiftTestModule(Logic(width: 20), Logic(width: 200),
            constant: BigInt.one << 100);
        await gtm.build();
        final vectors = [
          Vector({
            'a': BigInt.one << 200 | BigInt.one << 100,
            'b': BigInt.one << 100
          }, {
            'a_lshift_const': 0,
            'a_rshift_const': 0,
            'a_arshift_const': LogicValue.filled(20, LogicValue.zero),
            'a_lshift_b': 0,
            'a_rshift_b': 0,
            'a_arshift_b': LogicValue.filled(20, LogicValue.zero),
          }),
        ];
        await SimCompare.checkFunctionalVector(gtm, vectors);
        SimCompare.checkIverilogVector(gtm, vectors);
      });
    });

    test('And2Gate single bit', () async {
      final gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Or2Gate single bit', () async {
      final gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_or_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_or_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_or_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_or_b': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Xor2Gate single bit', () async {
      final gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_xor_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_xor_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_xor_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_xor_b': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Index Logic(8bit) by Logic test', () async {
      final gtm = IndexGateTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'original': 14, 'index': 0}, {'index_output': 0}),
        Vector({'original': 14, 'index': 2}, {'index_output': 1}),
        Vector({'original': 14, 'index': LogicValue.x},
            {'index_output': LogicValue.x}),
        Vector({'original': 14, 'index': 9}, {'index_output': LogicValue.x})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Index Logic(1bit) by Logic test', () async {
      final gtm = IndexGateTestModule(Logic(), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'original': LogicValue.x, 'index': LogicValue.x},
            {'index_output': LogicValue.x}),
        Vector({'original': LogicValue.x, 'index': 0},
            {'index_output': LogicValue.x}),
        Vector({'original': LogicValue.one, 'index': 0},
            {'index_output': LogicValue.one}),
        Vector({'original': LogicValue.zero, 'index': 0},
            {'index_output': LogicValue.zero})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Index Logic by an Integer test', () {
      final testLogic = Logic(width: 8)..put(14);
      final testLogicOne = Logic()..put(LogicValue.one);
      final testLogicZero = Logic()..put(LogicValue.zero);
      final testLogicInvalid = Logic()..put(LogicValue.x);

      expect(testLogic[0].value.toInt(), 0);
      expect(testLogic[2].value.toInt(), 1);

      expect(testLogicOne[0].value.toInt(), 1);
      expect(testLogicZero[0].value.toInt(), 0);
      expect(testLogicInvalid[0].value, LogicValue.x);

      expect(testLogicOne[-1].value.toInt(), 1);
      expect(testLogicZero[-1].value.toInt(), 0);
      expect(testLogicInvalid[-1].value, LogicValue.x);

      expect(() => testLogic[10], throwsA(isA<IndexError>()));
      expect(() => testLogicOne[1], throwsA(isA<IndexError>()));
      expect(() => testLogicZero[1], throwsA(isA<IndexError>()));
      expect(() => testLogicInvalid[1], throwsA(isA<IndexError>()));
    });

    test('index Logic(1bit) by Logic index out of bounds test', () {
      final testLogicOne = Logic()..put(LogicValue.one);
      final testLogicZero = Logic()..put(LogicValue.zero);
      final invalidIndex = Logic(width: 8)..put(1);

      expect(testLogicOne[invalidIndex].value, equals(LogicValue.x));
      expect(testLogicZero[invalidIndex].value, equals(LogicValue.x));
    });

    test('slice 1 bit wide Logic test', () {
      final testLogic = Logic(width: 8)..put(14);
      final testLogicOne = Logic()..put(LogicValue.one);
      final testLogicZero = Logic()..put(LogicValue.zero);
      final testLogicInvalid = Logic()..put(LogicValue.x);

      expect(testLogicOne.slice(0, 0), equals(testLogicOne));
      expect(testLogicZero.slice(0, 0), equals(testLogicZero));
      expect(testLogicInvalid.slice(0, 0), equals(testLogicInvalid));

      expect(() => testLogic.slice(0, 10), throwsA(isA<IndexError>()));
      expect(() => testLogicOne.slice(0, 1), throwsA(isA<IndexError>()));
      expect(() => testLogicZero.slice(0, 1), throwsA(isA<IndexError>()));
      expect(() => testLogicInvalid.slice(0, 1), throwsA(isA<IndexError>()));
    });

    test('Index Logic by does not accept input other than int or Logic', () {
      final testLogic = Logic(width: 8)..put(14);
      expect(() => testLogic[10.05], throwsException);
    });
  });
}
