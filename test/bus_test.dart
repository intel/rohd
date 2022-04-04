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
  Logic get aBar => output('a_bar');
  Logic get aAndB => output('a_and_b');
  Logic get aShrunk => output('a_shrunk');
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

    var aBar = addOutput('a_bar', width: a.width);
    var aAndB = addOutput('a_and_b', width: a.width);
    var aShrunk = addOutput('a_shrunk', width: 3);
    var aBJoined = addOutput('a_b_joined', width: a.width + b.width);
    var aPlusB = addOutput('a_plus_b', width: a.width);
    var a1 = addOutput('a1');

    aBar <= ~a;
    aAndB <= a & b;
    aShrunk <= a.slice(2, 0);
    aBJoined <= Swizzle([b, a]).out;
    a1 <= a[1];
    aPlusB <= a + b;
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
      var out = gtm.aShrunk;
      await gtm.build();
      a.put(0);
      expect(out.value.toInt(), equals(0));
      a.put(0xff);
      expect(out.value.toInt(), equals(bin('111')));
      a.put(0xf5);
      expect(out.value.toInt(), equals(5));
    });

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
      'a_shrunk': 3,
      'a_b_joined': 16,
      'a_plus_b': 8
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
        Vector({'a': 0}, {'a_shrunk': 0}),
        Vector({'a': 0xff}, {'a_shrunk': bin('111')}),
        Vector({'a': 0xf5}, {'a_shrunk': 5}),
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
