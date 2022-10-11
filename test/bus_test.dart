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
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class BusTestModule extends Module {
  // --- Getters ---
  Logic get aBar => output('a_bar');
  Logic get aAndB => output('a_and_b');
  Logic get aBJoined => output('a_b_joined');
  Logic get a1 => output('a1');
  Logic get aPlusB => output('a_plus_b');

  // Getters for Logic subset test variables
  Logic get aReversed => output('a_reversed');
  // --- Getters for Slicing
  Logic get aShrunk1 => output('a_shrunk1');
  Logic get aShrunk2 => output('a_shrunk2');
  Logic get aShrunk3 => output('a_shrunk3');
  Logic get aNegShrunk1 => output('a_neg_shrunk1');
  Logic get aNegShrunk2 => output('a_neg_shrunk2');
  Logic get aNegShrunk3 => output('a_neg_shrunk3');
  // --- Getters for Reverse Slicing
  Logic get aRSliced1 => output('a_rsliced1');
  Logic get aRSliced2 => output('a_rsliced2');
  Logic get aRSliced3 => output('a_rsliced3');
  Logic get aRNegativeSliced1 => output('a_r_neg_sliced1');
  Logic get aRNegativeSliced2 => output('a_r_neg_sliced2');
  Logic get aRNegativeSliced3 => output('a_r_neg_sliced3');
  // --- Getters for getRange
  Logic get aRange1 => output('a_range1');
  Logic get aRange2 => output('a_range2');
  Logic get aRange3 => output('a_range3');
  Logic get aNegativeRange1 => output('a_neg_range1');
  Logic get aNegativeRange2 => output('a_neg_range2');
  Logic get aNegativeRange3 => output('a_neg_range3');
  // --- Getters for operator[]
  // Logic get aOperatorIndexing1 => output('a_operator_indexing1');
  // Logic get aOperatorIndexing2 => output('a_operator_indexing2');
  // Logic get aOperatorIndexing3 => output('a_operator_indexing3');
  // Logic get aOperatorNegIndexing1 => output('a_operator_neg_indexing1');
  // Logic get aOperatorNegIndexing2 => output('a_operator_neg_indexing2');
  // Logic get aOperatorNegIndexing3 => output('a_operator_neg_indexing3');

  BusTestModule(Logic a, Logic b) : super(name: 'bustestmodule') {
    // --- Declaration ---
    if (a.width != b.width) {
      throw Exception('a and b must be same width, but found "$a" and "$b".');
    }
    if (a.width <= 3) {
      throw Exception('a must be more than width 3.');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    var aBar = addOutput('a_bar', width: a.width);
    var aAndB = addOutput('a_and_b', width: a.width);

    var aBJoined = addOutput('a_b_joined', width: a.width + b.width);
    var aPlusB = addOutput('a_plus_b', width: a.width);
    var a1 = addOutput('a1');

    // Logic Reverse value
    var aReversed = addOutput('a_reversed', width: a.width);
    // Slicing with Positive Indices
    var aShrunk1 = addOutput('a_shrunk1', width: 3);
    var aShrunk2 = addOutput('a_shrunk2', width: 2);
    var aShrunk3 = addOutput('a_shrunk3', width: 1);
    // Slicing with negative indices
    var aNegativeShrunk1 = addOutput('a_neg_shrunk1', width: 3);
    var aNegativeShrunk2 = addOutput('a_neg_shrunk2', width: 2);
    var aNegativeShrunk3 = addOutput('a_neg_shrunk3', width: 1);
    // Slicing and reversing the value
    var aRSliced1 = addOutput('a_rsliced1', width: 5);
    var aRSliced2 = addOutput('a_rsliced2', width: 2);
    var aRSliced3 = addOutput('a_rsliced3', width: 1);
    // Slicing and reversing the value via negative indices
    var aRNegativeSliced1 = addOutput('a_r_neg_sliced1', width: 5);
    var aRNegativeSliced2 = addOutput('a_r_neg_sliced2', width: 2);
    var aRNegativeSliced3 = addOutput('a_r_neg_sliced3', width: 1);
    // Getting the range of consecutive values over the Logic (subset)
    var aRange1 = addOutput('a_range1', width: 3);
    var aRange2 = addOutput('a_range2', width: 2);
    var aRange3 = addOutput('a_range3', width: 1);
    var aNegativeRange1 = addOutput('a_neg_range1', width: 3);
    var aNegativeRange2 = addOutput('a_neg_range2', width: 2);
    var aNegativeRange3 = addOutput('a_neg_range3', width: 1);
    // // Operator Indexing with positive index value
    // var aOperatorIndexing1 = addOutput('a_operator_indexing1', width: 1);
    // var aOperatorIndexing2 = addOutput('a_operator_indexing2', width: 1);
    // var aOperatorIndexing3 = addOutput('a_operator_indexing3', width: 1);
    // // Operator Indexing with negative index value
    // var aOperatorNegIndexing1 = addOutput('a_operator_neg_indexing1', width: 1);
    // var aOperatorNegIndexing2 = addOutput('a_operator_neg_indexing2', width: 1);
    // var aOperatorNegIndexing3 = addOutput('a_operator_neg_indexing3', width: 1);

    // --- Assignments ---
    aBar <= ~a;
    aAndB <= a & b;
    aBJoined <= [b, a].swizzle();
    a1 <= a[1];
    aPlusB <= a + b;

    // Logic Subset functionality
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
    aNegativeRange1 <= a.getRange(-3, 8); // NOTE: endIndex value is exclusive
    aNegativeRange2 <= a.getRange(-2, 8);
    aNegativeRange3 <= a.getRange(-1, 8);

    // aOperatorIndexing1 <= a[0];
    // aOperatorIndexing2 <= a[a.width - 1];
    // aOperatorIndexing3 <= a[4];
    // aOperatorNegIndexing1 <= a[-1];
    // aOperatorNegIndexing2 <= a[-2];
    // aOperatorNegIndexing3 <= a[-a.width];

    aReversed <= a.reversed;
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  group('functional', () {
    test('NotGate bus', () async {
      var a = Logic(width: 8);
      var gtm = BusTestModule(a, Logic(width: 8));
      var out = gtm.aBar;
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
      var a = Logic(width: 8);
      var b = Logic(width: 8);
      var gtm = BusTestModule(a, b);
      var out = gtm.aAndB;
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
      var a = Logic(width: 8);
      var b = Logic(width: 8);
      var gtm = BusTestModule(a, b);
      var out = gtm.aShrunk1;
      await gtm.build();
      a.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0xff);
      expect(out.value.toInt(), equals(bin('111')));
      a.put(0xf5);
      expect(out.value.toInt(), equals(5));
    });

    // test('Operator Indexing', () async {
    //   var a = Logic(width: 8);
    //   var b = Logic(width: 8);
    //   var gtm = BusTestModule(a, b);
    //   var out = gtm.aOperatorIndexing1;
    //   await gtm.build();
    //   a.put(0);
    //   expect(out.value.toInt(), equals(0));
    //   a.put(0xff);
    //   expect(out.value.toInt(), equals(bin('1')));
    //   a.put(0xc1);
    //   expect(out.value.toInt(), equals(bin('1')));
    // });

    test('Bus swizzle', () async {
      var a = Logic(width: 8);
      var b = Logic(width: 8);
      var gtm = BusTestModule(a, b);
      var out = gtm.aBJoined;
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
    var signalToWidthMap = {
      'a': 8,
      'b': 8,
      'a_bar': 8,
      'a_and_b': 8,
      'a_b_joined': 16,
      'a_plus_b': 8,

      // Slicing
      'a_shrunk1': 3,
      'a_shrunk2': 2,
      'a_shrunk3': 1,
      'a_neg_shrunk1': 3,
      'a_neg_shrunk2': 2,
      'a_neg_shrunk3': 1,
      // Reverse Slicing
      'a_rsliced1': 5,
      'a_rsliced2': 2,
      'a_rsliced3': 1,
      'a_r_neg_sliced1': 5,
      'a_r_neg_sliced2': 2,
      'a_r_neg_sliced3': 1,

      // getRange
      'a_range1': 3,
      'a_range2': 2,
      'a_range3': 1,
      'a_neg_range1': 3,
      'a_neg_range2': 2,
      'a_neg_range3': 1,

      // // operator[]
      // 'a_operator_indexing1': 3,
      // 'a_operator_indexing2': 2,
      // 'a_operator_indexing3': 1,
      // 'a_operator_neg_indexing1': 3,
      // 'a_operator_neg_indexing2': 2,
      // 'a_operator_neg_indexing3': 1,

      // Logic bus value Reversed
      'a_reversed': 8
    };
    test('NotGate bus', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0xff}, {'a_bar': 0}),
        Vector({'a': 0}, {'a_bar': 0xff}),
        Vector({'a': 0x55}, {'a_bar': 0xaa}),
        Vector({'a': 1}, {'a_bar': 0xfe}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('And2Gate bus', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1}),
        Vector({'a': 0xff, 'b': 0xaa}, {'a_and_b': 0xaa}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus shrink', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        // Positive Indexing
        // Test set 1
        Vector({'a': 0}, {'a_shrunk1': 0}),
        Vector({'a': 0xfa}, {'a_shrunk1': bin('010')}),
        Vector({'a': 0xab}, {'a_shrunk1': 3}),
        // Test set 2
        Vector({'a': 0}, {'a_shrunk2': 0}),
        Vector({'a': 0xec}, {'a_shrunk2': bin('00')}),
        Vector({'a': 0xfa}, {'a_shrunk2': 2}),
        // Test set 3
        Vector({'a': 0}, {'a_shrunk3': 0}),
        Vector({'a': 0xff}, {'a_shrunk3': bin('1')}),
        Vector({'a': 0xba}, {'a_shrunk3': 0}),

        // Negative Indexing
        // Test set 1
        Vector({'a': 0}, {'a_neg_shrunk1': 0}),
        Vector({'a': 0xfa}, {'a_neg_shrunk1': bin('010')}),
        Vector({'a': 0xab}, {'a_neg_shrunk1': 3}),
        // Test set 2
        Vector({'a': 0}, {'a_neg_shrunk2': 0}),
        Vector({'a': 0xec}, {'a_neg_shrunk2': bin('00')}),
        Vector({'a': 0xfa}, {'a_neg_shrunk2': 2}),
        // Test set 3
        Vector({'a': 0}, {'a_neg_shrunk3': 0}),
        Vector({'a': 0xff}, {'a_neg_shrunk3': bin('1')}),
        Vector({'a': 0xba}, {'a_neg_shrunk3': 0})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus reverse slice', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        // Positive Indexing
        // Test set 1
        Vector({'a': 0}, {'a_rsliced1': 0}),
        Vector({'a': 0xac}, {'a_rsliced1': bin('10101')}),
        Vector({'a': 0xf5}, {'a_rsliced1': 0xf}),
        // Test set 2
        Vector({'a': 0}, {'a_rsliced2': 0}),
        Vector({'a': 0xab}, {'a_rsliced2': bin('01')}),
        Vector({'a': 0xac}, {'a_rsliced2': 1}),
        // Test set 3
        Vector({'a': 0}, {'a_rsliced3': 0}),
        Vector({'a': 0xaf}, {'a_rsliced3': bin('1')}),
        Vector({'a': 0xaf}, {'a_rsliced3': 1}),

        // Negative Indexing
        // Test set 1
        Vector({'a': 0}, {'a_r_neg_sliced1': 0}),
        Vector({'a': 0xac}, {'a_r_neg_sliced1': bin('10101')}),
        Vector({'a': 0xf5}, {'a_r_neg_sliced1': 0xf}),
        // Test set 2
        Vector({'a': 0}, {'a_r_neg_sliced2': 0}),
        Vector({'a': 0xab}, {'a_r_neg_sliced2': bin('01')}),
        Vector({'a': 0xac}, {'a_r_neg_sliced2': 1}),
        // Test set 3
        Vector({'a': 0}, {'a_r_neg_sliced3': 0}),
        Vector({'a': 0xaf}, {'a_r_neg_sliced3': bin('1')}),
        Vector({'a': 0xaf}, {'a_r_neg_sliced3': 1})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus reversed', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0}, {'a_reversed': 0}),
        Vector({'a': 0xff}, {'a_reversed': 0xff}),
        Vector({'a': 0xf5}, {'a_reversed': 0xaf}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus range', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        // Positive Indexing
        // Test set 1
        Vector({'a': 0}, {'a_range1': 0}),
        Vector({'a': 0xaf}, {'a_range1': 5}),
        Vector({'a': bin('11000101')}, {'a_range1': bin('110')}),
        // Test set 2
        Vector({'a': 0}, {'a_range2': 0}),
        Vector({'a': 0xaf}, {'a_range2': 2}),
        Vector({'a': bin('10111111')}, {'a_range2': bin('10')}),
        // Test set 3
        Vector({'a': 0}, {'a_range3': 0}),
        Vector({'a': 0x80}, {'a_range3': 1}),
        Vector({'a': bin('10000000')}, {'a_range3': bin('1')}),

        // Negative Indexing
        // Test set 1
        Vector({'a': 0}, {'a_neg_range1': 0}),
        Vector({'a': 0xaf}, {'a_neg_range1': 5}),
        Vector({'a': bin('11000101')}, {'a_neg_range1': bin('110')}),
        // Test set 2
        Vector({'a': 0}, {'a_neg_range2': 0}),
        Vector({'a': 0xaf}, {'a_neg_range2': 2}),
        Vector({'a': bin('10111111')}, {'a_neg_range2': bin('10')}),
        // Test set 3
        Vector({'a': 0}, {'a_neg_range3': 0}),
        Vector({'a': 0x80}, {'a_neg_range3': 1}),
        Vector({'a': bin('10000000')}, {'a_neg_range3': bin('1')}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus swizzle', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_b_joined': 0}),
        Vector({'a': 0xff, 'b': 0xff}, {'a_b_joined': 0xffff}),
        Vector({'a': 0xff, 'b': 0}, {'a_b_joined': 0xff}),
        Vector({'a': 0, 'b': 0xff}, {'a_b_joined': 0xff00}),
        Vector({'a': 0xaa, 'b': 0x55}, {'a_b_joined': 0x55aa}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('Bus bit', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0}, {'a1': 0}),
        Vector({'a': 0xff}, {'a1': 1}),
        Vector({'a': 0xf5}, {'a1': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });

    test('add busses', () async {
      var gtm = BusTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'a_plus_b': 0}),
        Vector({'a': 0, 'b': 1}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 0}, {'a_plus_b': 1}),
        Vector({'a': 1, 'b': 1}, {'a_plus_b': 2}),
        Vector({'a': 6, 'b': 7}, {'a_plus_b': 13}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(
          gtm.generateSynth(), gtm.runtimeType.toString(), vectors,
          signalToWidthMap: signalToWidthMap);
      expect(simResult, equals(true));
    });
  });
}
