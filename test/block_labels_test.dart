// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// block_labels_test.dart
// Unit test for block labels (e.g. always_comb, always_ff, case)
//
// 2025 March 6
// Author: Andrew Capatina <andrew.capatina@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class LabeledCasesModule extends Module {
  Logic control;
  Logic a;
  Logic b;
  String caseLabel;

  LabeledCasesModule(
      this.control, this.a, this.b, [this.caseLabel='cases']) {
    control = addInput('control', control);
    a = addInput('a', a);
    b = addInput('b', b);
    final out = addOutput('out');
    out <= cases(
      control, {LogicValue.zero: a, LogicValue.one: b},
      label: caseLabel);
  }
}

class LabeledCaseModule extends Module {
  Logic a;
  Logic b;
  String firstCaseItemLabel;
  String secondCaseItemLabel;
  String defaultLabel;

  LabeledCaseModule(
      this.a, this.b, [this.firstCaseItemLabel='caseItem1',
      this.secondCaseItemLabel='caseItem2', this.defaultLabel='default1']) {
    a = addInput('a', a);
    b = addInput('b', b);
    final out = addOutput('out');

    final aXorB = a ^ b;  
    Combinational([
      Case(
        aXorB,
        [
          CaseItem(Const(LogicValue.ofString('0')),
            [out < 1], label: firstCaseItemLabel),
          CaseItem(Const(LogicValue.ofString('1')),
            [out < 0], label: secondCaseItemLabel)
        ], defaultItem: [out < 0], defaultLabel: defaultLabel),
    ]);
  }
}

class LabeledIfModule extends Module {
  Logic a;
  Logic b;

  Logic get out => output('out');

  String alwaysCombLabel;
  String ifLabel;
  String ifElseLabel;
  String elseLabel;

  LabeledIfModule(
      this.a, this.b, [this.alwaysCombLabel='comb_1', this.ifLabel='if_1',
      this.ifElseLabel='if_else_1', this.elseLabel='else_1']) {
    a = addInput('a', a);
    b = addInput('b', b);
    final out = addOutput('out');

    Combinational([
      If.block([
        Iff(a.eq(0) & b.eq(0), [
          out < 0,
        ], label: ifLabel),
        ElseIf(a.eq(1) & b.eq(0), [
          out < 1,
        ], label: ifElseLabel),
        Else([
          out < 0,
        ], label: elseLabel)
      ]),
    ], label: alwaysCombLabel);
  }
}

class LabeledChainSequentialModule extends Module {
  Logic reset;
  Logic d;
  Logic get q => output('q');
  final clk = SimpleClockGenerator(10).clk;

  String firstFfLabel;
  String secondFfLabel;

  LabeledChainSequentialModule(
      this.reset, this.d, [this.firstFfLabel='ff_1',
      this.secondFfLabel='ff_2']) {
    reset = addInput('reset', reset);
    d = addInput('d', d);
    final q = addOutput('q');

    final qInternal = LogicNet();
    Sequential(
      clk,
      reset: reset,
      resetValues: {
        qInternal: 0
      },
      [
        qInternal < d
      ],
      label: firstFfLabel
    );
    Sequential(
      clk,
      reset: reset,
      resetValues: {
        q: 0
      },
      [
        q < qInternal
      ],
      label: secondFfLabel
    );
  }
}

class LabeledMultiBlockModule extends Module {
  Logic a;
  Logic b;
  Logic c;
  Logic d;

  Logic get out_0 => output('out_0');
  Logic get out_1 => output('out_1');

  String firstBlockLabel;
  String secondBlockLabel;

  LabeledMultiBlockModule(
      this.a, this.b, this.c, this.d, [this.firstBlockLabel='block_0',
      this.secondBlockLabel='block_1']) {
    a = addInput('a', a);
    b = addInput('b', b);
    c = addInput('c', c);
    d = addInput('d', d);    
    final out_0 = addOutput('out_0');
    final out_1 = addOutput('out_1');

    Combinational([out_0 < a & b], label: firstBlockLabel);
    Combinational([out_1 < c ^ d], label: secondBlockLabel);
  }
}

class LabeledSsaModule extends Module {
  String firstBlockLabel;
  String secondBlockLabel;

  LabeledSsaModule(Logic a, [this.firstBlockLabel='block_0',
      this.secondBlockLabel='block_1']) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);
    final c = addOutput('c', width: a.width);

    final intermediate_0 = Logic(name: 'intermediate_0', width: a.width);
    final intermediate_1 = Logic(name: 'intermediate_1', width: a.width);

    final inc_0 = IncrModule(intermediate_0);
    final inc_1 = IncrModule(intermediate_1);

    Combinational.ssa((s) => [
          s(intermediate_0) < a,
          s(intermediate_0) < inc_0.result,
          s(intermediate_0) < inc_0.result,
        ], label: firstBlockLabel);

    Combinational.ssa((s) => [
          s(intermediate_1) < c,
          s(intermediate_1) < inc_1.result,
          s(intermediate_1) < inc_1.result,
        ], label: secondBlockLabel);
    b <= intermediate_0;
    c <= intermediate_1;
  }
}

class IncrModule extends Module {
  Logic get result => output('result');
  IncrModule(Logic toIncr) : super(name: 'incr') {
    toIncr = addInput('toIncr', toIncr, width: toIncr.width);
    addOutput('result', width: toIncr.width);
    result <= toIncr + 1;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('case statements', () {
    final shorthandCaseVectors = [
      Vector({'control': 0, 'a': 0, 'b': 0}, {'out': 0}),
      Vector({'control': 0, 'a': 0, 'b': 1}, {'out': 0}),
      Vector({'control': 0, 'a': 1, 'b': 0}, {'out': 1}),
      Vector({'control': 0, 'a': 1, 'b': 1}, {'out': 1}),
      Vector({'control': 1, 'a': 0, 'b': 0}, {'out': 0}),
      Vector({'control': 1, 'a': 0, 'b': 1}, {'out': 1}),
      Vector({'control': 1, 'a': 1, 'b': 0}, {'out': 0}),
      Vector({'control': 1, 'a': 1, 'b': 1}, {'out': 1}),
    ];
    final caseVectors = [
      Vector({'a': 0, 'b': 0}, {'out': 1}),
      Vector({'a': 0, 'b': 1}, {'out': 0}),
      Vector({'a': 1, 'b': 0}, {'out': 0}),
      Vector({'a': 1, 'b': 1}, {'out': 1}),
    ];
    test('valid shorthand case', () async {
      final gtm = LabeledCasesModule(Logic(), Logic(), Logic());
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, shorthandCaseVectors);
      final simResult = SimCompare.iverilogVector(gtm, shorthandCaseVectors);
      expect(simResult, equals(true));
    });    
    test('valid case', () async {

      final gtm = LabeledCaseModule(Logic(), Logic());
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, caseVectors);
      final simResult = SimCompare.iverilogVector(gtm, caseVectors);
      expect(simResult, equals(true));
    });

    test('same case items labels', () async {
      final gtm = LabeledCaseModule(
        Logic(), Logic(), 'caseItem2');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, caseVectors);
      final simResult = SimCompare.iverilogVector(
        gtm, caseVectors, buildOnly: true);
      expect(simResult, equals(false));
    });

    test('same case item and default label', () async {
      final gtm = LabeledCaseModule(
        Logic(), Logic(), 'caseItem1', 'caseItem2', 'caseItem1');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, caseVectors);
      final simResult = SimCompare.iverilogVector(
        gtm, caseVectors, buildOnly: true);
      expect(simResult, equals(false));
    });    
  });

  group('if/else if/else blocks', () {
    final vectors = [
      Vector({'a': 0, 'b': 0}, {'out': 0}),
      Vector({'a': 0, 'b': 1}, {'out': 0}),
      Vector({'a': 1, 'b': 0}, {'out': 1}),
      Vector({'a': 1, 'b': 1}, {'out': 0}),
    ];
    test('valid case', () async {
      final gtm = LabeledIfModule(
        Logic(), Logic());
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('same if and else if labels', () async {
      final gtm = LabeledIfModule(
        Logic(), Logic(), 'comb_1', 'if_1', 'if_1');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });

    test('same if and else labels', () async {
      final gtm = LabeledIfModule(
        Logic(), Logic(), 'comb_1', 'if_1', 'else_if_1', 'if_1');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });

    test('same else if and else labels', () async {
      final gtm = LabeledIfModule(
        Logic(), Logic(), 'comb_1', 'if_1', 'else_if_1', 'else_if_1');
      await gtm.build();    
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });
  });

  group('seqeuntial blocks', () {
    final vectors = [
      Vector({'reset': 1}, {}),
      Vector({}, {'q': 0}),
      Vector({'reset': 0, 'd': 0}, {}),
      Vector({}, {'q': 0}),
      Vector({'reset': 0, 'd': 1}, {}),
      Vector({}, {'q': 0}),
      Vector({'reset': 0, 'd': 1}, {}),
      Vector({}, {'q': 1}),
      Vector({'reset': 1, 'd': 0}, {}),
      Vector({}, {'q': 0}),
      Vector({'reset': 1, 'd': 1}, {}),
      Vector({}, {'q': 0}),
    ];
    test('valid labels', () async {
      final gtm = LabeledChainSequentialModule(
        Logic(), Logic());
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('same labels', () async {
      final gtm = LabeledChainSequentialModule(
        Logic(), Logic(), 'ff_0', 'ff_0');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });
  });

  group('multi block modules with same scope', () {
    test('valid labels', () async {
      final gtm = LabeledMultiBlockModule(
        Logic(), Logic(), Logic(), Logic());
      await gtm.build();
      final vectors = [
        Vector({'a': 1, 'b': 0, 'c': 1, 'd': 0}, {'out_0': 0, 'out_1': 1})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('blocks of same scope with same name', () async {
      final gtm = LabeledMultiBlockModule(
        Logic(), Logic(), Logic(), Logic(), 'block_0', 'block_0');
      await gtm.build();
      final vectors = [
        Vector({'a': 1, 'b': 0, 'c': 1, 'd': 0}, {'out_0': 0, 'out_1': 1})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });
  });

  group('combinational ssa', () {
    final vectors = [
      Vector({'a': 3}, {'b': LogicValue.x, 'c': LogicValue.x})
    ];
    test('valid labels', () async {
      final gtm = LabeledSsaModule(Logic(width: 8));
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('same block labels', () async {
      final gtm = LabeledSsaModule(Logic(width: 8), 'block_0', 'block_0');
      await gtm.build();
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
        gtm, vectors, buildOnly: true);
      expect(simResult, equals(false));
    });    
  });
}
