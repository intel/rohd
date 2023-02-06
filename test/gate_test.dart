/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// gate_test.dart
/// Unit tests for basic gates
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///
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

class ShiftTestModule extends Module {
  int constantInt;
  ShiftTestModule(Logic a, Logic b, {this.constantInt = 3})
      : super(name: 'shifttestmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aRshiftB = addOutput('a_rshift_b', width: a.width);
    final aLshiftB = addOutput('a_lshift_b', width: a.width);
    final aArshiftB = addOutput('a_arshift_b', width: a.width);

    final aRshiftConst = addOutput('a_rshift_const', width: a.width);
    final aLshiftConst = addOutput('a_lshift_const', width: a.width);
    final aArshiftConst = addOutput('a_arshift_const', width: a.width);

    final c = Const(constantInt, width: b.width);
    aRshiftB <= a >>> b;
    aLshiftB <= a << b;
    aArshiftB <= a >> b;
    aRshiftConst <= a >>> c;
    aLshiftConst <= a << c;
    aArshiftConst <= a >> c;
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

  group('simcompare', () {
    test('NotGate single bit', () async {
      final gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 1}, {'a_bar': 0}),
        Vector({'a': 0}, {'a_bar': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
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

    test('Mux bus', () async {
      final mod = MuxWrapper(Logic(), Logic(width: 8), Logic(width: 8));
      await mod.build();
      final vectors = [
        Vector({'control': 1, 'd0': 12, 'd1': 15}, {'y': 15}),
        Vector({'control': 0, 'd0': 18, 'd1': 7}, {'y': 18}),
        Vector({'control': 0, 'd0': 3, 'd1': 6}, {'y': 3}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });

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
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
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
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
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
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('lshift int', () async {
      final gtm =
          ShiftTestModule(Logic(width: 3), Logic(width: 8), constantInt: 1);
      await gtm.build();
      final vectors = [
        Vector({'a': bin('010')}, {'a_lshift_const': bin('100')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('rshift int', () async {
      final gtm =
          ShiftTestModule(Logic(width: 3), Logic(width: 8), constantInt: 1);
      await gtm.build();
      final vectors = [
        Vector({'a': bin('010')}, {'a_rshift_const': bin('001')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('arshift int', () async {
      final gtm =
          ShiftTestModule(Logic(width: 3), Logic(width: 8), constantInt: 1);
      await gtm.build();
      final vectors = [
        Vector({'a': bin('010')}, {'a_arshift_const': bin('001')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
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

      expect(() => testLogic[10], throwsException);
      expect(() => testLogicOne[1], throwsException);
      expect(() => testLogicZero[1], throwsException);
      expect(() => testLogicInvalid[1], throwsException);
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

      expect(() => testLogic.slice(0, 10), throwsException);
      expect(() => testLogicOne.slice(0, 1), throwsException);
      expect(() => testLogicZero.slice(0, 1), throwsException);
      expect(() => testLogicInvalid.slice(0, 1), throwsException);
    });

    test('Index Logic by does not accept input other than int or Logic', () {
      final testLogic = Logic(width: 8)..put(14);
      expect(() => testLogic[10.05], throwsException);
    });
  });
}
