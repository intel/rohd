/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// gate_test.dart
/// Unit tests for basic gates
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class ContentionModule extends Module {
  Logic get y => output('y');
  ContentionModule() : super(name: 'contentionmodule') {
    var y = addOutput('y');
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

    var aBar = addOutput('a_bar');
    var aAndB = addOutput('a_and_b');
    var aOrB = addOutput('a_or_b');
    var aXorB = addOutput('a_xor_b');

    aBar <= ~a;
    aAndB <= a & b;
    aOrB <= a | b;
    aXorB <= a ^ b;
  }
}

class UnaryGateTestModule extends Module {
  UnaryGateTestModule(Logic a) : super(name: 'ugatetestmodule') {
    a = addInput('a', a, width: a.width);

    var aAnd = addOutput('a_and');
    var aOr = addOutput('a_or');
    var aXor = addOutput('a_xor');

    aAnd <= a.and();
    aOr <= a.or();
    aXor <= a.xor();
  }
}

//TODO: add tests to shift logic by const, and const by logic

class ShiftTestModule extends Module {
  int constantInt;
  ShiftTestModule(Logic a, Logic b, {this.constantInt = 3}) : super(name: 'shifttestmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    var aRshiftB = addOutput('a_rshift_b', width: a.width);
    var aLshiftB = addOutput('a_lshift_b', width: a.width);
    var aArshiftB = addOutput('a_arshift_b', width: a.width);

  
    var aRshiftConst  = addOutput('a_rshift_const', width: a.width);
    var aLshiftConst  = addOutput('a_lshift_const', width: a.width);
    var aArshiftConst = addOutput('a_arshift_const', width: a.width);

    var c = Const(constantInt, width: b.width);
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
    var y = addOutput('y', width: d0.width);

    y <= Mux(control, d1, d0).y;
  }
}

void main() {

  tearDown(() {
    Simulator.reset();
  });

  group('functional', () {
    test('NotGate single bit', () async {
      var a = Logic();
      var gtm = GateTestModule(a, Logic());
      var out = gtm.aBar;
      await gtm.build(); 
      a.put(1); expect(out.valueInt, equals(0));
      a.put(0); expect(out.valueInt, equals(1));
    });

    test('Contention not gate', () async {
      var mod = ContentionModule();
      await mod.build();
      mod.y.put(0);
      expect(mod.y.bit, equals(LogicValue.x));
    });
    
    test('And2Gate single bit', () async {
      var a = Logic();
      var b = Logic();
      var gtm = GateTestModule(a, b);
      var out = gtm.aAndB;
      await gtm.build();
      a.put(0); b.put(0); expect(out.valueInt, equals(0));
      a.put(0); b.put(1); expect(out.valueInt, equals(0));
      a.put(1); b.put(0); expect(out.valueInt, equals(0));
      a.put(1); b.put(1); expect(out.valueInt, equals(1));
    });

    test('Or2Gate single bit', () async {
      var a = Logic();
      var b = Logic();
      var gtm = GateTestModule(a, b);
      var out = gtm.aOrB;
      await gtm.build();
      a.put(0); b.put(0); expect(out.valueInt, equals(0));
      a.put(0); b.put(1); expect(out.valueInt, equals(1));
      a.put(1); b.put(0); expect(out.valueInt, equals(1));
      a.put(1); b.put(1); expect(out.valueInt, equals(1));
    });

    test('Xor2Gate single bit', () async {
      var a = Logic();
      var b = Logic();
      var gtm = GateTestModule(a, b);
      var out = gtm.aXorB;
      await gtm.build();
      a.put(0); b.put(0); expect(out.valueInt, equals(0));
      a.put(0); b.put(1); expect(out.valueInt, equals(1));
      a.put(1); b.put(0); expect(out.valueInt, equals(1));
      a.put(1); b.put(1); expect(out.valueInt, equals(0));
    });
  });

  group('simcompare', () {
    test('NotGate single bit', () async {
      var gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      var vectors = [
        Vector({'a': 1}, {'a_bar': 0}),
        Vector({'a': 0}, {'a_bar': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('unary and', () async {
      var gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('0000')}, {'a_and': 0}),
        Vector({'a': bin('1010')}, {'a_and': 0}),
        Vector({'a': bin('1111')}, {'a_and': 1}),
        Vector({'a': bin('0001')}, {'a_and': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: {
          'a': 4,
        }
      );
      expect(simResult, equals(true));
    });

    test('unary or', () async {
      var gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('0000')}, {'a_or': 0}),
        Vector({'a': bin('1010')}, {'a_or': 1}),
        Vector({'a': bin('1111')}, {'a_or': 1}),
        Vector({'a': bin('0001')}, {'a_or': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: {
          'a': 4,
        }
      );
      expect(simResult, equals(true));
    });

    test('unary xor', () async {
      var gtm = UnaryGateTestModule(Logic(width: 4));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('0000')}, {'a_xor': 0}),
        Vector({'a': bin('1010')}, {'a_xor': 0}),
        Vector({'a': bin('1111')}, {'a_xor': 0}),
        Vector({'a': bin('0001')}, {'a_xor': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: {
          'a': 4,
        }
      );
      expect(simResult, equals(true));
    });

    test('Mux single bit', () async {
      var mod = MuxWrapper(Logic(), Logic(), Logic());
      await mod.build();
      var vectors = [
        Vector({'control': 1, 'd0': 0, 'd1': 1}, {'y': 1}),
        Vector({'control': 0, 'd0': 0, 'd1': 1}, {'y': 0}),
        Vector({'control': 0, 'd0': 1, 'd1': 1}, {'y': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('Mux bus', () async {
      var mod = MuxWrapper(Logic(), Logic(width:8), Logic(width:8));
      await mod.build();
      var vectors = [
        Vector({'control': 1, 'd0': 12, 'd1': 15}, {'y': 15}),
        Vector({'control': 0, 'd0': 18, 'd1': 7}, {'y': 18}),
        Vector({'control': 0, 'd0': 3, 'd1': 6}, {'y': 3}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors,
        signalToWidthMap: {
          'd0':8,
          'd1':8,
          'y':8
        }
      );
      expect(simResult, equals(true));
    });

    var shiftVectorWidthMap = {
      'a': 3,
      'b': 8,
      'a_rshift_b': 3,
      'a_lshift_b': 3,
      'a_arshift_b': 3,
      'a_rshift_const': 3,
      'a_lshift_const': 3,
      'a_arshift_const': 3,
    };

    test('lshift logic', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010'), 'b': 0}, {'a_lshift_b': bin('010')}),
        Vector({'a': bin('010'), 'b': 1}, {'a_lshift_b': bin('100')}),
        Vector({'a': bin('010'), 'b': 2}, {'a_lshift_b': bin('000')}),
        Vector({'a': bin('010'), 'b': 6}, {'a_lshift_b': bin('000')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('rshift logic', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010'), 'b': 0}, {'a_rshift_b': bin('010')}),
        Vector({'a': bin('010'), 'b': 1}, {'a_rshift_b': bin('001')}),
        Vector({'a': bin('010'), 'b': 2}, {'a_rshift_b': bin('000')}),
        Vector({'a': bin('010'), 'b': 6}, {'a_rshift_b': bin('000')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('arshift logic', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8));
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010'), 'b': 0}, {'a_arshift_b': bin('010')}),
        Vector({'a': bin('010'), 'b': 1}, {'a_arshift_b': bin('001')}),
        Vector({'a': bin('010'), 'b': 2}, {'a_arshift_b': bin('000')}),
        Vector({'a': bin('010'), 'b': 6}, {'a_arshift_b': bin('000')}),
        Vector({'a': bin('110'), 'b': 0}, {'a_arshift_b': bin('110')}),
        Vector({'a': bin('110'), 'b': 6}, {'a_arshift_b': bin('111')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('lshift int', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8), constantInt: 1);
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010')}, {'a_lshift_const': bin('100')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('rshift int', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8), constantInt: 1);
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010')}, {'a_rshift_const': bin('001')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('arshift int', () async {
      var gtm = ShiftTestModule(Logic(width:3), Logic(width:8), constantInt: 1);
      await gtm.build();
      var vectors = [
        Vector({'a': bin('010')}, {'a_arshift_const': bin('001')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
        signalToWidthMap: shiftVectorWidthMap
      );
      expect(simResult, equals(true));
    });

    test('And2Gate single bit', () async {
      var gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('Or2Gate single bit', () async {
      var gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_or_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_or_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_or_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_or_b': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('Xor2Gate single bit', () async {
      var gtm = GateTestModule(Logic(), Logic());
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_xor_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_xor_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_xor_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_xor_b': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });
  });  

}