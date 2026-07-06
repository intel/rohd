// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_vector_test.dart
// Parallel SystemC simulation tests for all modules tested with iverilog.
//
// 2026 May 7
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:math';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

// ===== Modules from flop_test.dart =====

class FlopTestModule extends Module {
  FlopTestModule(Logic a, {Logic? en, Logic? reset, dynamic resetValue})
      : super(name: 'floptestmodule') {
    a = addInput('a', a, width: a.width);
    if (en != null) {
      en = addInput('en', en);
    }
    if (reset != null) {
      reset = addInput('reset', reset);
    }
    if (resetValue != null && resetValue is Logic) {
      resetValue = addInput('resetValue', resetValue, width: a.width);
    }
    final y = addOutput('y', width: a.width);
    final clk = SimpleClockGenerator(10).clk;
    y <= flop(clk, a, en: en, reset: reset, resetValue: resetValue);
  }
}

// ===== Modules from counter_test.dart =====

class Counter extends Module {
  final int width;
  Logic get val => output('val');
  Counter(Logic en, Logic reset, {this.width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    final val = addOutput('val', width: width);
    final nextVal = Logic(name: 'nextVal', width: width);
    nextVal <= val + 1;
    Sequential.multi([
      SimpleClockGenerator(10).clk,
      reset
    ], [
      If(reset, then: [
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}

// ===== Modules from comparison_test.dart =====

class ComparisonTestModule extends Module {
  final int c;
  ComparisonTestModule(Logic a, Logic b, {this.c = 5})
      : super(name: 'gatetestmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aEqB = addOutput('a_eq_b');
    final aNeqB = addOutput('a_neq_b');
    final aLtB = addOutput('a_lt_b');
    final aLteB = addOutput('a_lte_b');
    final aGtB = addOutput('a_gt_b');
    final aGteB = addOutput('a_gte_b');
    final aGtOperatorB = addOutput('a_gt_operator_b');
    final aGteOperatorB = addOutput('a_gte_operator_b');

    final aEqC = addOutput('a_eq_c');
    final aNeqC = addOutput('a_neq_c');
    final aLtC = addOutput('a_lt_c');
    final aLteC = addOutput('a_lte_c');
    final aGtC = addOutput('a_gt_c');
    final aGteC = addOutput('a_gte_c');
    final aGtOperatorC = addOutput('a_gt_operator_c');
    final aGteOperatorC = addOutput('a_gte_operator_c');

    aEqB <= a.eq(b);
    aNeqB <= a.neq(b);
    aLtB <= a.lt(b);
    aLteB <= a.lte(b);
    aGtB <= a.gt(b);
    aGteB <= a.gte(b);
    aGtOperatorB <= (a > b);
    aGteOperatorB <= (a >= b);

    aEqC <= a.eq(c);
    aNeqC <= a.neq(c);
    aLtC <= a.lt(c);
    aLteC <= a.lte(c);
    aGtC <= a.gt(c);
    aGteC <= a.gte(c);
    aGtOperatorC <= (a > c);
    aGteOperatorC <= (a >= c);
  }
}

// ===== Modules from arithmetic_shift_right_test.dart =====

class SraUnsignedTestModule extends Module {
  Logic get result => output('result');
  SraUnsignedTestModule(Logic toShift, Logic shiftAmount, Logic maskBit) {
    toShift = addInput('toShift', toShift, width: toShift.width);
    shiftAmount =
        addInput('shiftAmount', shiftAmount, width: shiftAmount.width);
    maskBit = addInput('maskBit', maskBit);
    addOutput('result', width: toShift.width);
    result <= (toShift >> shiftAmount) & maskBit.replicate(toShift.width);
  }
}

// ===== Modules from collapse_test.dart =====

class CollapseTestModule extends Module {
  CollapseTestModule(Logic a, Logic b) : super(name: 'collapsetestmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');
    final f = addOutput('f');

    final x = Logic(name: 'x');
    final y = Logic(name: 'y');
    final z = Logic(name: 'z', naming: Naming.mergeable);
    c <= a & b;
    d <= a & b;
    x <= a;
    y <= x;
    e <= a & b & c & x & y;
    z <= b & y;
    f <= a & z;

    Logic(name: 'internal') <= ~z;
  }
}

// ===== Modules from extend_test.dart =====

class ExtendModule extends Module {
  ExtendModule(Logic a, int newWidth, ExtendType extendType) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: newWidth);
    if (extendType == ExtendType.zero) {
      b <= a.zeroExtend(newWidth);
    } else {
      b <= a.signExtend(newWidth);
    }
  }
}

enum ExtendType { zero, sign }

class WithSetModule extends Module {
  WithSetModule(Logic a, int startIndex, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final c = addOutput('c', width: a.width);
    c <= a.withSet(startIndex, b);
  }
}

// ===== Modules from bus_test.dart =====

class BusTestModule extends Module {
  BusTestModule(Logic a, Logic b) : super(name: 'bustestmodule') {
    if (a.width != b.width) {
      throw Exception('a and b must be same width.');
    }
    if (a.width <= 3) {
      throw Exception('a must be more than width 3.');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aBar = addOutput('a_bar', width: a.width);
    final aAndB = addOutput('a_and_b', width: a.width);
    final aBJoined = addOutput('a_b_joined', width: a.width + b.width);
    final aPlusB = addOutput('a_plus_b', width: a.width);
    final a1 = addOutput('a1');
    final expressionBitSelect = addOutput('expression_bit_select', width: 4);

    final aReversed = addOutput('a_reversed', width: a.width);
    final aShrunk1 = addOutput('a_shrunk1', width: 3);
    final aShrunk2 = addOutput('a_shrunk2', width: 2);
    final aShrunk3 = addOutput('a_shrunk3');
    final aNegativeShrunk1 = addOutput('a_neg_shrunk1', width: 3);
    final aNegativeShrunk2 = addOutput('a_neg_shrunk2', width: 2);
    final aNegativeShrunk3 = addOutput('a_neg_shrunk3');
    final aRSliced1 = addOutput('a_rsliced1', width: 5);
    final aRSliced2 = addOutput('a_rsliced2', width: 2);
    final aRSliced3 = addOutput('a_rsliced3');
    final aRNegativeSliced1 = addOutput('a_r_neg_sliced1', width: 5);
    final aRNegativeSliced2 = addOutput('a_r_neg_sliced2', width: 2);
    final aRNegativeSliced3 = addOutput('a_r_neg_sliced3');
    final aRange1 = addOutput('a_range1', width: 3);
    final aRange2 = addOutput('a_range2', width: 2);
    final aRange3 = addOutput('a_range3');
    final aRange4 = addOutput('a_range4', width: 3);
    final aNegativeRange1 = addOutput('a_neg_range1', width: 3);
    final aNegativeRange2 = addOutput('a_neg_range2', width: 2);
    final aNegativeRange3 = addOutput('a_neg_range3');
    final aNegativeRange4 = addOutput('a_neg_range4', width: 3);
    final aOperatorIndexing1 = addOutput('a_operator_indexing1');
    final aOperatorIndexing2 = addOutput('a_operator_indexing2');
    final aOperatorIndexing3 = addOutput('a_operator_indexing3');
    final aOperatorNegIndexing1 = addOutput('a_operator_neg_indexing1');
    final aOperatorNegIndexing2 = addOutput('a_operator_neg_indexing2');
    final aOperatorNegIndexing3 = addOutput('a_operator_neg_indexing3');

    aBar <= ~a;
    aAndB <= a & b;
    aBJoined <= [b, a].swizzle();
    a1 <= a[1];
    aPlusB <= a + b;

    aShrunk1 <= a.slice(2, 0);
    aShrunk2 <= a.slice(1, 0);
    aShrunk3 <= a.slice(0, 0);
    aNegativeShrunk1 <= a.slice(-6, 0);
    aNegativeShrunk2 <= a.slice(-7, 0);
    aNegativeShrunk3 <= a.slice(-8, 0);

    aRSliced1 <= a.slice(3, 7);
    aRSliced2 <= a.slice(6, 7);
    aRSliced3 <= a.slice(7, 7);
    aRNegativeSliced1 <= a.slice(-5, -1);
    aRNegativeSliced2 <= a.slice(-2, -1);
    aRNegativeSliced3 <= a.slice(-1, -1);

    aRange1 <= a.getRange(5, 8);
    aRange2 <= a.getRange(6, 8);
    aRange3 <= a.getRange(7, 8);
    aRange4 <= a.getRange(5);
    aNegativeRange1 <= a.getRange(-3, 8);
    aNegativeRange2 <= a.getRange(-2, 8);
    aNegativeRange3 <= a.getRange(-1, 8);
    aNegativeRange4 <= a.getRange(-3);

    aOperatorIndexing1 <= a.elements[0];
    aOperatorIndexing2 <= a[a.width - 1];
    aOperatorIndexing3 <= a[4];
    aOperatorNegIndexing1 <= a[-a.width];
    aOperatorNegIndexing2 <= a[-1];
    aOperatorNegIndexing3 <= a[-2];

    aReversed <= a.reversed;

    expressionBitSelect <=
        [aBJoined, aShrunk1, aRange1, aRSliced1, aPlusB].swizzle().slice(3, 0);
  }
}

class ConstBusModule extends Module {
  ConstBusModule(int c, {required bool subset}) {
    final outWidth = subset ? 8 : 16;
    addOutput('const_subset', width: outWidth) <=
        Const(c, width: 16).getRange(0, outWidth);
  }
}

class SingleBitBusSubsetMod extends Module {
  SingleBitBusSubsetMod(Logic oneBit) {
    oneBit = addInput('oneBit', oneBit);
    addOutput('result') <= BusSubset(oneBit, 0, 0).subset;
  }
}

class SelectTestModule extends Module {
  SelectTestModule(Logic a1, Logic a2, Logic a3, Logic b, {Logic? defaultValue})
      : super(name: 'selecttestmodule') {
    a1 = addInput('a1', a1, width: a1.width);
    a2 = addInput('a2', a2, width: a2.width);
    a3 = addInput('a3', a3, width: a3.width);
    b = addInput('b', b, width: b.width);

    if (defaultValue != null) {
      defaultValue =
          addInput('defaultValue', defaultValue, width: defaultValue.width);
      _selectWithDefault(a1, a2, a3, b, defaultValue);
    } else {
      _selectWithout(a1, a2, a3, b);
    }
  }

  void _selectWithout(Logic a1, Logic a2, Logic a3, Logic b) {
    final selectIndexValue = addOutput('selectIndexValue', width: a1.width);
    final selectFromValue = addOutput('selectFromValue', width: a1.width);
    final logicList = <Logic>[a1, a2, a3];
    selectIndexValue <= logicList.selectIndex(b);
    selectFromValue <= b.selectFrom(logicList);
  }

  void _selectWithDefault(
      Logic a1, Logic a2, Logic a3, Logic b, Logic defaultValue) {
    final selectFromValue = addOutput('selectFromValue', width: a1.width);
    final selectIndexValue = addOutput('selectIndexValue', width: a1.width);
    final logicList = <Logic>[a1, a2, a3];
    selectFromValue <= b.selectFrom(logicList, defaultValue: defaultValue);
    selectIndexValue <= logicList.selectIndex(b, defaultValue: defaultValue);
  }
}

// ===== Modules from conditionals_test.dart =====

class LoopyCombModuleSsa extends Module {
  Logic get a => input('a');
  Logic get x => output('x');
  LoopyCombModuleSsa(Logic a) : super(name: 'loopycombmodule') {
    a = addInput('a', a);
    final x = addOutput('x');
    Combinational.ssa((s) => [
          s(x) < a,
          s(x) < ~s(x),
        ]);
  }
}

class CaseModule extends Module {
  CaseModule(Logic a, Logic b) : super(name: 'casemodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');

    Combinational([
      Case(
          [b, a].swizzle(),
          [
            CaseItem(Const(LogicValue.ofString('01')), [c < 1, d < 0]),
            CaseItem(Const(LogicValue.ofString('10')), [c < 1, d < 0]),
          ],
          defaultItem: [c < 0, d < 1],
          conditionalType: ConditionalType.unique),
      CaseZ(
          [b, a].rswizzle(),
          [
            CaseItem(Const(LogicValue.ofString('1z')), [e < 1])
          ],
          defaultItem: [e < 0],
          conditionalType: ConditionalType.priority)
    ]);
  }
}

class IfBlockModule extends Module {
  IfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      If.block([
        Iff(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class SingleIfBlockModule extends Module {
  SingleIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');
    Combinational([
      If.block([Iff.s(a, c < 1)])
    ]);
  }
}

class ElseIfBlockModule extends Module {
  ElseIfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');

    Combinational([
      If.block([
        ElseIf(a & ~b, [c < 1, d < 0]),
        ElseIf(b & ~a, [c < 1, d < 0]),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class SingleElseIfBlockModule extends Module {
  SingleElseIfBlockModule(Logic a) : super(name: 'singleifblockmodule') {
    a = addInput('a', a);
    final c = addOutput('c');
    final d = addOutput('d');
    Combinational([
      If.block([
        ElseIf.s(a, c < 1),
        Else([c < 0, d < 1])
      ])
    ]);
  }
}

class CombModule extends Module {
  CombModule(Logic a, Logic b, Logic d) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');
    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Combinational([
      If(a, then: [
        y < a,
        z < b,
        x < a & b,
        q < d,
      ], orElse: [
        If(b, then: [
          y < b,
          z < a,
          q < 13,
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SequentialModule extends Module {
  SequentialModule(Logic a, Logic b, Logic d) : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');
    final x = addOutput('x');
    d = addInput('d', d, width: d.width);
    final q = addOutput('q', width: d.width);

    Sequential(SimpleClockGenerator(10).clk, [
      If(a, then: [
        q < d,
        y < a,
        z < b,
        x < ~x,
      ], orElse: [
        x < a,
        If(b, then: [
          y < b,
          z < a
        ], orElse: [
          y < 0,
          z < 1,
        ])
      ])
    ]);
  }
}

class SingleIfModule extends Module {
  SingleIfModule(Logic a) : super(name: 'combmodule') {
    a = addInput('a', a);
    final q = addOutput('q');
    Combinational([If.s(a, q < 1)]);
  }
}

class SingleIfOrElseModule extends Module {
  SingleIfOrElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final q = addOutput('q');
    final x = addOutput('x');
    Combinational([If.s(a, q < 1, x < 1)]);
  }
}

class SingleElseModule extends Module {
  SingleElseModule(Logic a, Logic b) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final q = addOutput('q');
    final x = addOutput('x');
    Combinational([
      If.block([Iff.s(a, q < 1), Else.s(x < 1)])
    ]);
  }
}

class SignalRedrivenSequentialModule extends Module {
  SignalRedrivenSequentialModule(Logic a, Logic b, Logic d,
      {required bool allowRedrive})
      : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final q = addOutput('q', width: d.width);
    d = addInput('d', d, width: d.width);
    final k = addOutput('k', width: 8);
    Sequential(
      SimpleClockGenerator(10).clk,
      [
        If(a, then: [k < k, q < k, q < d])
      ],
      allowMultipleAssignments: allowRedrive,
    );
  }
}

// ===== Modules from assignment_test.dart =====

class ConstAssignModule extends Module {
  ConstAssignModule() {
    final out = addOutput('out');
    final val = Logic(name: 'val');
    val <= Const(1);
    Combinational([out < val]);
  }

  Logic get out => output('out');
}

// =========================================================================
//  Tests
// =========================================================================

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  tearDownAll(SimCompare.cleanupSystemCCache);

  // ===== Flop tests (from flop_test.dart) =====
  group('flop', () {
    test('flop bit', () async {
      final ftm = FlopTestModule(Logic());
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'a': 0}, {}),
        Vector({'a': 1}, {'y': 0}),
        Vector({'a': 1}, {'y': 1}),
        Vector({'a': 0}, {'y': 1}),
        Vector({'a': 0}, {'y': 0}),
      ]);
    });

    test('flop bit with enable', () async {
      final ftm = FlopTestModule(Logic(), en: Logic());
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'a': 0, 'en': 1}, {}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 1}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 1, 'en': 0}, {'y': 1}),
        Vector({'a': 0, 'en': 0}, {'y': 1}),
        Vector({'a': 0, 'en': 1}, {'y': 1}),
        Vector({'a': 1, 'en': 1}, {'y': 0}),
        Vector({'a': 0, 'en': 0}, {'y': 1}),
        Vector({'a': 1, 'en': 0}, {'y': 1}),
      ]);
    });

    test('flop bus', () async {
      final ftm = FlopTestModule(Logic(width: 8));
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'a': 0}, {}),
        Vector({'a': 0xff}, {'y': 0}),
        Vector({'a': 0xaa}, {'y': 0xff}),
        Vector({'a': 0x55}, {'y': 0xaa}),
        Vector({'a': 0x1}, {'y': 0x55}),
      ]);
    });

    test('flop bus with enable', () async {
      final ftm = FlopTestModule(Logic(width: 8), en: Logic());
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'a': 0, 'en': 1}, {}),
        Vector({'a': 0xff, 'en': 1}, {'y': 0}),
        Vector({'a': 0xaa, 'en': 1}, {'y': 0xff}),
        Vector({'a': 0x55, 'en': 1}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x55}),
        Vector({'a': 0, 'en': 1}, {'y': 0x1}),
        Vector({'a': 0xff, 'en': 1}, {'y': 0}),
        Vector({'a': 0xaa, 'en': 1}, {'y': 0xff}),
        Vector({'a': 0x55, 'en': 0}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 0}, {'y': 0xaa}),
        Vector({'a': 0x55, 'en': 1}, {'y': 0xaa}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x55}),
        Vector({'a': 0x55, 'en': 0}, {'y': 0x1}),
        Vector({'a': 0x1, 'en': 1}, {'y': 0x1}),
      ]);
    });

    test('flop bus reset, no reset value', () async {
      final ftm = FlopTestModule(Logic(width: 8), reset: Logic());
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'reset': 1}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 0}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ]);
    });

    test('flop bus reset, const reset value', () async {
      final ftm =
          FlopTestModule(Logic(width: 8), reset: Logic(), resetValue: 3);
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'reset': 1}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 3}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ]);
    });

    test('flop bus reset, logic reset value', () async {
      final ftm = FlopTestModule(Logic(width: 8),
          reset: Logic(), resetValue: Logic(width: 8));
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'reset': 1, 'resetValue': 5}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 5}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ]);
    });

    test('flop bus no reset, const reset value', () async {
      final ftm = FlopTestModule(Logic(width: 8), resetValue: 9);
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({}, {}),
        Vector({'a': 0xa5}, {}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ]);
    });

    test('flop bus, enable, reset, const reset value', () async {
      final ftm = FlopTestModule(Logic(width: 8),
          en: Logic(), reset: Logic(), resetValue: 12);
      await ftm.build();
      SimCompare.checkSystemCVector(ftm, [
        Vector({'reset': 1, 'en': 0}, {}),
        Vector({'reset': 0, 'a': 0xa5}, {'y': 12}),
        Vector({}, {'y': 12}),
        Vector({'en': 1}, {'y': 12}),
        Vector({'a': 0xff}, {'y': 0xa5}),
        Vector({}, {'y': 0xff}),
      ]);
    });
  });

  // ===== Counter tests (from counter_test.dart) =====
  group('counter', () {
    test('counter', () async {
      final counter = Counter(Logic(), Logic());
      await counter.build();
      SimCompare.checkSystemCVector(counter, [
        Vector({'en': 0, 'reset': 0}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ]);
    });
  });

  // ===== Comparison tests (from comparison_test.dart) =====
  group('comparison', () {
    test('compares', () async {
      final gtm = ComparisonTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      SimCompare.checkSystemCVector(gtm, [
        Vector({
          'a': 0,
          'b': 0
        }, {
          'a_eq_b': 1,
          'a_neq_b': 0,
          'a_lt_b': 0,
          'a_lte_b': 1,
          'a_gt_b': 0,
          'a_gte_b': 1,
          'a_gt_operator_b': 0,
          'a_gte_operator_b': 1,
          'a_eq_c': 0,
          'a_neq_c': 1,
          'a_lt_c': 1,
          'a_lte_c': 1,
          'a_gt_c': 0,
          'a_gte_c': 0,
          'a_gt_operator_c': 0,
          'a_gte_operator_c': 0,
        }),
        Vector({
          'a': 5,
          'b': 6
        }, {
          'a_eq_b': 0,
          'a_neq_b': 1,
          'a_lt_b': 1,
          'a_lte_b': 1,
          'a_gt_b': 0,
          'a_gte_b': 0,
          'a_gt_operator_b': 0,
          'a_gte_operator_b': 0,
          'a_eq_c': 1,
          'a_neq_c': 0,
          'a_lt_c': 0,
          'a_lte_c': 1,
          'a_gt_c': 0,
          'a_gte_c': 1,
          'a_gt_operator_c': 0,
          'a_gte_operator_c': 1,
        }),
        Vector({
          'a': 9,
          'b': 7
        }, {
          'a_eq_b': 0,
          'a_neq_b': 1,
          'a_lt_b': 0,
          'a_lte_b': 0,
          'a_gt_b': 1,
          'a_gte_b': 1,
          'a_gt_operator_b': 1,
          'a_gte_operator_b': 1,
          'a_eq_c': 0,
          'a_neq_c': 1,
          'a_lt_c': 0,
          'a_lte_c': 0,
          'a_gt_c': 1,
          'a_gte_c': 1,
          'a_gt_operator_c': 1,
          'a_gte_operator_c': 1,
        }),
      ]);
    });
  });

  // ===== Arithmetic shift right tests =====
  group('arithmetic shift right', () {
    test('shift right and mask', () async {
      final mod =
          SraUnsignedTestModule(Logic(width: 32), Logic(width: 32), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'toShift': 0xe0000000, 'shiftAmount': 4, 'maskBit': 1},
            {'result': 0xfe000000}),
        Vector({'toShift': 0x10000000, 'shiftAmount': 4, 'maskBit': 1},
            {'result': 0x01000000}),
        Vector({'toShift': 0xe0000000, 'shiftAmount': 4, 'maskBit': 0},
            {'result': 0}),
      ]);
    });
  });

  // ===== Collapse tests =====
  group('collapse', () {
    test('collapse functional', () async {
      final mod = CollapseTestModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1, 'b': 1}, {'c': 1, 'd': 1, 'e': 1, 'f': 1}),
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 0, 'e': 0, 'f': 0}),
      ]);
    });
  });

  // ===== Extend tests =====
  group('extend', () {
    Future<void> extendVectors(
        List<Vector> vectors, int newWidth, ExtendType extendType,
        {int originalWidth = 8}) async {
      final mod =
          ExtendModule(Logic(width: originalWidth), newWidth, extendType);
      await mod.build();
      SimCompare.checkSystemCVector(mod, vectors);
    }

    test('zero extend same width', () async {
      await extendVectors([
        Vector({'a': 0}, {'b': 0}),
        Vector({'a': 0xff}, {'b': 0xff}),
        Vector({'a': 0x5a}, {'b': 0x5a}),
      ], 8, ExtendType.zero);
    });

    test('sign extend same width', () async {
      await extendVectors([
        Vector({'a': 0}, {'b': 0}),
        Vector({'a': 0xff}, {'b': 0xff}),
        Vector({'a': 0x5a}, {'b': 0x5a}),
      ], 8, ExtendType.sign);
    });

    test('zero extend pads 0s', () async {
      await extendVectors([
        Vector({'a': 0xff}, {'b': 0xff}),
        Vector({'a': 0x5a}, {'b': 0x5a}),
      ], 12, ExtendType.zero);
    });

    test('sign extend positive pads 0s', () async {
      await extendVectors([
        Vector({'a': 0x5a}, {'b': 0x5a}),
      ], 12, ExtendType.sign);
    });

    test('sign extend negative pads 1s', () async {
      await extendVectors([
        Vector({'a': 0xff}, {'b': 0xfff}),
      ], 12, ExtendType.sign);
    });

    test('sign extend single bit(0) pads 0s', () async {
      await extendVectors([
        Vector({'a': LogicValue.zero}, {'b': 0x000}),
      ], 12, ExtendType.sign, originalWidth: 1);
    });

    test('sign extend single bit(1) pads 1s', () async {
      await extendVectors([
        Vector({'a': LogicValue.one}, {'b': 0xfff}),
      ], 12, ExtendType.sign, originalWidth: 1);
    });
  });

  group('withSet', () {
    Future<void> withSetVectors(
        List<Vector> vectors, int startIndex, int updateWidth) async {
      final mod =
          WithSetModule(Logic(width: 8), startIndex, Logic(width: updateWidth));
      await mod.build();
      SimCompare.checkSystemCVector(mod, vectors);
    }

    test('setting same width', () async {
      await withSetVectors([
        Vector({'a': 0x23, 'b': 0xff}, {'c': 0xff}),
        Vector({'a': 0x45, 'b': 0x5a}, {'c': 0x5a}),
      ], 0, 8);
    });

    test('setting at front', () async {
      await withSetVectors([
        Vector({'a': 0x23, 'b': 0xf}, {'c': 0x2f}),
        Vector({'a': 0x4a, 'b': 0x5}, {'c': 0x45}),
      ], 0, 4);
    });

    test('setting at end', () async {
      await withSetVectors([
        Vector({'a': 0x23, 'b': 0xf}, {'c': 0xf3}),
        Vector({'a': 0x4a, 'b': 0x5}, {'c': 0x5a}),
      ], 4, 4);
    });

    test('setting in the middle', () async {
      await withSetVectors([
        Vector({'a': 0xff, 'b': 0x0}, {'c': bin('11000011')}),
        Vector(
            {'a': bin('01111110'), 'b': bin('0110')}, {'c': bin('01011010')}),
      ], 2, 4);
    });
  });

  // ===== Bus tests =====
  group('bus', () {
    test('single-bit bus subset', () async {
      final mod = SingleBitBusSubsetMod(Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'oneBit': 0}, {'result': 0}),
        Vector({'oneBit': 1}, {'result': 1}),
      ]);
    });

    test('const subset', () async {
      final mod = ConstBusModule(0xabcd, subset: true);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({}, {'const_subset': 0xcd}),
      ]);
    });

    test('const assignment', () async {
      final mod = ConstBusModule(0xabcd, subset: false);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({}, {'const_subset': 0xabcd}),
      ]);
    });

    // All tests below share the same BusTestModule — compile once
    group('BusTestModule', () {
      SystemCExecutable? exe;

      setUpAll(() async {
        final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
        await gtm.build();
        exe = SimCompare.buildSystemCExecutable(gtm);
      });

      tearDownAll(() {
        exe?.cleanup();
      });

      test('NotGate bus', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0xff}, {'a_bar': 0}),
          Vector({'a': 0}, {'a_bar': 0xff}),
          Vector({'a': 0x55}, {'a_bar': 0xaa}),
          Vector({'a': 1}, {'a_bar': 0xfe}),
        ]);
      });

      test('And2Gate bus', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0, 'b': 0}, {'a_and_b': 0}),
          Vector({'a': 0, 'b': 1}, {'a_and_b': 0}),
          Vector({'a': 1, 'b': 0}, {'a_and_b': 0}),
          Vector({'a': 1, 'b': 1}, {'a_and_b': 1}),
          Vector({'a': 0xff, 'b': 0xaa}, {'a_and_b': 0xaa}),
        ]);
      });

      test('Operator indexing', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': bin('11111110')}, {'a_operator_indexing1': 0}),
          Vector({'a': bin('10000000')}, {'a_operator_indexing2': 1}),
          Vector({'a': bin('11101111')}, {'a_operator_indexing3': 0}),
          Vector({'a': bin('11111110')}, {'a_operator_neg_indexing1': 0}),
          Vector({'a': bin('10000000')}, {'a_operator_neg_indexing2': 1}),
          Vector({'a': bin('10111111')}, {'a_operator_neg_indexing3': 0}),
        ]);
      });

      test('Bus shrink', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0}, {'a_shrunk1': 0}),
          Vector({'a': 0xfa}, {'a_shrunk1': bin('010')}),
          Vector({'a': 0xab}, {'a_shrunk1': 3}),
          Vector({'a': 0}, {'a_shrunk2': 0}),
          Vector({'a': 0xec}, {'a_shrunk2': bin('00')}),
          Vector({'a': 0xfa}, {'a_shrunk2': 2}),
          Vector({'a': 0}, {'a_shrunk3': 0}),
          Vector({'a': 0xff}, {'a_shrunk3': bin('1')}),
          Vector({'a': 0xba}, {'a_shrunk3': 0}),
          Vector({'a': 0}, {'a_neg_shrunk1': 0}),
          Vector({'a': 0xfa}, {'a_neg_shrunk1': bin('010')}),
          Vector({'a': 0xab}, {'a_neg_shrunk1': 3}),
          Vector({'a': 0}, {'a_neg_shrunk2': 0}),
          Vector({'a': 0xec}, {'a_neg_shrunk2': bin('00')}),
          Vector({'a': 0xfa}, {'a_neg_shrunk2': 2}),
          Vector({'a': 0}, {'a_neg_shrunk3': 0}),
          Vector({'a': 0xff}, {'a_neg_shrunk3': bin('1')}),
          Vector({'a': 0xba}, {'a_neg_shrunk3': 0}),
        ]);
      });

      test('Bus reverse slice', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0}, {'a_rsliced1': 0}),
          Vector({'a': 0xac}, {'a_rsliced1': bin('10101')}),
          Vector({'a': 0xf5}, {'a_rsliced1': 0xf}),
          Vector({'a': 0}, {'a_rsliced2': 0}),
          Vector({'a': 0xab}, {'a_rsliced2': bin('01')}),
          Vector({'a': 0xac}, {'a_rsliced2': 1}),
          Vector({'a': 0}, {'a_rsliced3': 0}),
          Vector({'a': 0xaf}, {'a_rsliced3': bin('1')}),
          Vector({'a': 0xaf}, {'a_rsliced3': 1}),
          Vector({'a': 0}, {'a_r_neg_sliced1': 0}),
          Vector({'a': 0xac}, {'a_r_neg_sliced1': bin('10101')}),
          Vector({'a': 0xf5}, {'a_r_neg_sliced1': 0xf}),
          Vector({'a': 0}, {'a_r_neg_sliced2': 0}),
          Vector({'a': 0xab}, {'a_r_neg_sliced2': bin('01')}),
          Vector({'a': 0xac}, {'a_r_neg_sliced2': 1}),
          Vector({'a': 0}, {'a_r_neg_sliced3': 0}),
          Vector({'a': 0xaf}, {'a_r_neg_sliced3': bin('1')}),
          Vector({'a': 0xaf}, {'a_r_neg_sliced3': 1}),
        ]);
      });

      test('Bus reversed', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0}, {'a_reversed': 0}),
          Vector({'a': 0xff}, {'a_reversed': 0xff}),
          Vector({'a': 0xf5}, {'a_reversed': 0xaf}),
        ]);
      });

      test('Bus range', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0}, {'a_range1': 0}),
          Vector({'a': 0xaf}, {'a_range1': 5}),
          Vector({'a': bin('11000101')}, {'a_range1': bin('110')}),
          Vector({'a': 0}, {'a_range2': 0}),
          Vector({'a': 0xaf}, {'a_range2': 2}),
          Vector({'a': bin('10111111')}, {'a_range2': bin('10')}),
          Vector({'a': 0}, {'a_range3': 0}),
          Vector({'a': 0x80}, {'a_range3': 1}),
          Vector({'a': bin('10000000')}, {'a_range3': bin('1')}),
          Vector({'a': 0}, {'a_range4': 0}),
          Vector({'a': 0xaf}, {'a_range4': 5}),
          Vector({'a': bin('11000101')}, {'a_range4': bin('110')}),
          Vector({'a': 0}, {'a_neg_range1': 0}),
          Vector({'a': 0xaf}, {'a_neg_range1': 5}),
          Vector({'a': bin('11000101')}, {'a_neg_range1': bin('110')}),
          Vector({'a': 0}, {'a_neg_range2': 0}),
          Vector({'a': 0xaf}, {'a_neg_range2': 2}),
          Vector({'a': bin('10111111')}, {'a_neg_range2': bin('10')}),
          Vector({'a': 0}, {'a_neg_range3': 0}),
          Vector({'a': 0x80}, {'a_neg_range3': 1}),
          Vector({'a': bin('10000000')}, {'a_neg_range3': bin('1')}),
          Vector({'a': 0}, {'a_neg_range4': 0}),
          Vector({'a': 0xaf}, {'a_neg_range4': 5}),
          Vector({'a': bin('11000101')}, {'a_neg_range4': bin('110')}),
        ]);
      });

      test('Bus swizzle', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0, 'b': 0}, {'a_b_joined': 0}),
          Vector({'a': 0xff, 'b': 0xff}, {'a_b_joined': 0xffff}),
          Vector({'a': 0xff, 'b': 0}, {'a_b_joined': 0xff}),
          Vector({'a': 0, 'b': 0xff}, {'a_b_joined': 0xff00}),
          Vector({'a': 0xaa, 'b': 0x55}, {'a_b_joined': 0x55aa}),
        ]);
      });

      test('Bus bit', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0}, {'a1': 0}),
          Vector({'a': 0xff}, {'a1': 1}),
          Vector({'a': 0xf5}, {'a1': 0}),
        ]);
      });

      test('add busses', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
          Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
          Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
          Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
          Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
        ]);
      });

      test('expression bit select', () {
        if (exe == null) {
          return;
        }
        SimCompare.checkSystemCVectors(exe!, [
          Vector({'a': 1, 'b': 1}, {'expression_bit_select': 2}),
        ]);
      });
    }); // end BusTestModule group

    test('selectFrom and selectIndex', () async {
      final gtm = SelectTestModule(Logic(width: 8), Logic(width: 8),
          Logic(width: 8), Logic(width: (log(8) / log(2)).ceil()));
      await gtm.build();
      SimCompare.checkSystemCVector(gtm, [
        Vector({'a1': 1, 'a2': 2, 'a3': 3, 'b': 1},
            {'selectIndexValue': 2, 'selectFromValue': 2}),
        Vector({'a1': 1, 'a2': 2, 'a3': 3, 'b': 0},
            {'selectIndexValue': 1, 'selectFromValue': 1}),
        Vector({'a1': 1, 'a2': 2, 'a3': 3, 'b': 2},
            {'selectIndexValue': 3, 'selectFromValue': 3}),
      ]);
    });

    test('selectFrom with default Value', () async {
      final gtm = SelectTestModule(Logic(width: 8), Logic(width: 8),
          Logic(width: 8), Logic(width: (log(8) / log(2)).ceil()),
          defaultValue: Logic(width: 8));
      await gtm.build();
      SimCompare.checkSystemCVector(gtm, [
        Vector({'a1': 1, 'a2': 2, 'a3': 3, 'b': 4, 'defaultValue': 5},
            {'selectFromValue': 5, 'selectIndexValue': 5}),
      ]);
    });
  });

  // ===== Conditionals tests =====
  group('conditionals', () {
    test('conditional comb', () async {
      final mod = CombModule(Logic(), Logic(), Logic(width: 10));
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 0, 'b': 0, 'd': 5},
            {'y': 0, 'z': 1, 'x': LogicValue.x, 'q': LogicValue.x}),
        Vector({'a': 0, 'b': 1, 'd': 6},
            {'y': 1, 'z': 0, 'x': LogicValue.x, 'q': 13}),
        Vector({'a': 1, 'b': 0, 'd': 7}, {'y': 1, 'z': 0, 'x': 0, 'q': 7}),
        Vector({'a': 1, 'b': 1, 'd': 8}, {'y': 1, 'z': 1, 'x': 1, 'q': 8}),
      ]);
    });

    test('iffblock comb', () async {
      final mod = IfBlockModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ]);
    });

    test('single iffblock comb', () async {
      final mod = SingleIfBlockModule(Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1}, {'c': 1}),
      ]);
    });

    test('elseifblock comb', () async {
      final mod = ElseIfBlockModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ]);
    });

    test('single elseifblock comb', () async {
      final mod = SingleElseIfBlockModule(Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1}, {'c': 1}),
        Vector({'a': 0}, {'c': 0, 'd': 1}),
      ]);
    });

    test('case comb', () async {
      final mod = CaseModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1, 'e': 0}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0, 'e': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0, 'e': 1}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1, 'e': 1}),
      ]);
    });

    test('conditional ff', () async {
      final mod = SequentialModule(Logic(), Logic(), Logic(width: 8));
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1, 'd': 1}, {}),
        Vector({'a': 0, 'b': 0, 'd': 2}, {'q': 1}),
        Vector({'a': 0, 'b': 1, 'd': 3}, {'y': 0, 'z': 1, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 0, 'd': 4}, {'y': 1, 'z': 0, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 1, 'd': 5}, {'y': 1, 'z': 0, 'x': 1, 'q': 4}),
        Vector({}, {'y': 1, 'z': 1, 'x': 0, 'q': 5}),
      ]);
    });

    test('loopy comb ssa', () async {
      final mod = LoopyCombModuleSsa(Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 0}, {'x': 1}),
        Vector({'a': 1}, {'x': 0}),
      ]);
    });

    test('single if', () async {
      final mod = SingleIfModule(Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1}, {'q': 1}),
      ]);
    });

    test('single if or else', () async {
      final mod = SingleIfOrElseModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1}, {'q': 1}),
        Vector({'a': 0}, {'x': 1}),
      ]);
    });

    test('single else', () async {
      final mod = SingleElseModule(Logic(), Logic());
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1}, {'q': 1}),
        Vector({'a': 0}, {'x': 1}),
      ]);
    });

    test('redrive allowed', () async {
      final mod = SignalRedrivenSequentialModule(
          Logic(), Logic(), Logic(width: 8),
          allowRedrive: true);
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({'a': 1, 'd': 1}, {}),
        Vector({'a': 1, 'b': 0, 'd': 2}, {'q': 1}),
        Vector({'a': 1, 'b': 0, 'd': 3}, {'q': 2}),
      ]);
    });
  });

  // ===== Assignment tests =====
  group('assignment', () {
    test('const comb assignment', () async {
      final mod = ConstAssignModule();
      await mod.build();
      SimCompare.checkSystemCVector(mod, [
        Vector({}, {'out': 1}),
      ]);
    });
  });
}
