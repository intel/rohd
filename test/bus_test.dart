/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus_test.dart
/// Unit tests for bus-related operations
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class BusTestModule extends Module {
  Logic get aBar => output('a_bar');
  Logic get aAndB => output('a_and_b');
  Logic get aShrunk => output('a_shrunk');
  Logic get aRSliced => output('a_rsliced');
  Logic get aReversed => output('a_reversed');
  Logic get aRange => output('a_range');
  Logic get aBJoined => output('a_b_joined');
  Logic get a1 => output('a1');
  Logic get aPlusB => output('a_plus_b');

  BusTestModule(Logic a, Logic b) : super(name: 'bustestmodule') {
    if (a.width != b.width) {
      throw Exception('a and b must be same width, but found "$a" and "$b".');
    }
    if (a.width <= 3) {
      throw Exception('a must be more than width 3.');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aBar = addOutput('a_bar', width: a.width);
    final aAndB = addOutput('a_and_b', width: a.width);
    final aShrunk = addOutput('a_shrunk', width: 3);
    final aRSliced = addOutput('a_rsliced', width: 5);
    final aReversed = addOutput('a_reversed', width: a.width);
    final aRange = addOutput('a_range', width: 3);
    final aBJoined = addOutput('a_b_joined', width: a.width + b.width);
    final aPlusB = addOutput('a_plus_b', width: a.width);
    final a1 = addOutput('a1');
    final expressionBitSelect = addOutput('expression_bit_select', width: 4);

    aBar <= ~a;
    aAndB <= a & b;
    aShrunk <= a.slice(2, 0);
    aRSliced <= a.slice(3, 7);
    aReversed <= a.reversed;
    aRange <= a.getRange(5, 8);
    aBJoined <= [b, a].swizzle();
    a1 <= a[1];
    aPlusB <= a + b;
    expressionBitSelect <=
        [aBJoined, aShrunk, aRange, aRSliced, aPlusB].swizzle().slice(3, 0);
  }
}

void main() {
  tearDown(Simulator.reset);

  group('functional', () {
    test('NotGate bus', () async {
      final a = Logic(width: 8);
      final gtm = BusTestModule(a, Logic(width: 8));
      final out = gtm.aBar;
      await gtm.build();
      a.put(0xff);
      expect(out.value.toInt(), equals(0));
      a.put(0);
      expect(out.value.toInt(), equals(0xff));
      a.put(0x55);
      expect(out.value.toInt(), equals(0xaa));
      a.put(0x1);
      expect(out.value.toInt(), equals(0xfe));
    });

    test('And2Gate bus', () async {
      final a = Logic(width: 8);
      final b = Logic(width: 8);
      final gtm = BusTestModule(a, b);
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
      a.put(0xff);
      b.put(0xaa);
      expect(out.value.toInt(), equals(0xaa));
    });

    test('Bus shrink', () async {
      final a = Logic(width: 8);
      final b = Logic(width: 8);
      final gtm = BusTestModule(a, b);
      final out = gtm.aShrunk;
      await gtm.build();
      a.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0xff);
      expect(out.value.toInt(), equals(bin('111')));
      a.put(0xf5);
      expect(out.value.toInt(), equals(5));
    });

    test('Bus swizzle', () async {
      final a = Logic(width: 8);
      final b = Logic(width: 8);
      final gtm = BusTestModule(a, b);
      final out = gtm.aBJoined;
      await gtm.build();
      a.put(0);
      b.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0xff);
      b.put(0xff);
      expect(out.value.toInt(), equals(0xffff));
      a.put(0xff);
      b.put(0);
      expect(out.value.toInt(), equals(0xff));
      a.put(0);
      b.put(0xff);
      expect(out.value.toInt(), equals(0xff00));
      a.put(0xaa);
      b.put(0x55);
      expect(out.value.toInt(), equals(0x55aa));
    });
  });

  group('simcompare', () {
    final signalToWidthMap = {
      'a': 8,
      'b': 8,
      'a_bar': 8,
      'a_and_b': 8,
      'a_shrunk': 3,
      'a_rsliced': 5,
      'a_reversed': 8,
      'a_range': 3,
      'a_b_joined': 16,
      'a_plus_b': 8,
      'expression_bit_select': 4,
    };
    test('NotGate bus', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0xff}, {'a_bar': 0}),
        Vector({'a': 0}, {'a_bar': 0xff}),
        Vector({'a': 0x55}, {'a_bar': 0xaa}),
        Vector({'a': 1}, {'a_bar': 0xfe}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('And2Gate bus', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1}),
        Vector({'a': 0xff, 'b': 0xaa}, {'a_and_b': 0xaa}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus shrink', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0}, {'a_shrunk': 0}),
        Vector({'a': 0xff}, {'a_shrunk': bin('111')}),
        Vector({'a': 0xf5}, {'a_shrunk': 5}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus reverse slice', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0}, {'a_rsliced': 0}),
        Vector({'a': 0xff}, {'a_rsliced': bin('11111')}),
        Vector({'a': 0xf5}, {'a_rsliced': 0xf}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus reversed', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0}, {'a_reversed': 0}),
        Vector({'a': 0xff}, {'a_reversed': 0xff}),
        Vector({'a': 0xf5}, {'a_reversed': 0xaf}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus range', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0}, {'a_range': 0}),
        Vector({'a': 0xff}, {'a_range': 7}),
        Vector({'a': bin('10100101')}, {'a_range': bin('101')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus swizzle', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_b_joined': 0}),
        Vector({'a': 0xff, 'b': 0xff}, {'a_b_joined': 0xffff}),
        Vector({'a': 0xff, 'b': 0}, {'a_b_joined': 0xff}),
        Vector({'a': 0, 'b': 0xff}, {'a_b_joined': 0xff00}),
        Vector({'a': 0xaa, 'b': 0x55}, {'a_b_joined': 0x55aa}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus bit', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0}, {'a1': 0}),
        Vector({'a': 0xff}, {'a1': 1}),
        Vector({'a': 0xf5}, {'a1': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('add busses', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
        Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('expression bit select', () async {
      final gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({'a': 1, 'b': 1}, {'expression_bit_select': 2}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });
  });
}
