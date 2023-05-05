// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array_test.dart
// Tests for LogicArray
//
// 2023 May 2
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SimpleLAPassthrough extends Module {
  Logic get laOut => output('laOut');
  SimpleLAPassthrough(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
        laIn;

    //TODO: add some more interesting logic
  }
}

class PackAndUnpackPassthrough extends Module implements SimpleLAPassthrough {
  Logic get laOut => output('laOut');
  PackAndUnpackPassthrough(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final intermediate = Logic(name: 'intermediate', width: laIn.width);

    intermediate <= laIn;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
        intermediate;
  }
}

class PackAndUnpackWithArraysPassthrough extends Module
    implements SimpleLAPassthrough {
  Logic get laOut => output('laOut');
  PackAndUnpackWithArraysPassthrough(LogicArray laIn,
      {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final intermediate1 = Logic(name: 'intermediate1', width: laIn.width);
    final intermediate3 = Logic(name: 'intermediate3', width: laIn.width);

    // unpack with reversed dimensions
    final intermediate2 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate2', numDimensionsUnpacked: intermediateUnpacked);

    intermediate1 <= laIn;
    intermediate2 <= intermediate1;
    intermediate3 <= intermediate2;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
        intermediate3;
  }
}

class RearrangeArraysPassthrough extends Module implements SimpleLAPassthrough {
  Logic get laOut => output('laOut');
  RearrangeArraysPassthrough(LogicArray laIn, {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    // rearrange with reversed dimensions
    final intermediate = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numDimensionsUnpacked: intermediateUnpacked);

    intermediate <= laIn;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
        intermediate;
  }
}

//TODO: test module hierarchy
//TODO: test constant assignments (to part and all of array)
//TODO: Test packed and unpacked arrays both
//TODO: test passing packed into unpacked, unpacked into packed
//TODO: test that unpacked and packed are properly instantiated in SV

//TODO: file issue tracking that unpacked arrays not fully tested
// https://github.com/steveicarus/iverilog/issues/482
// https://github.com/verilator/verilator/issues/2907

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('construct LogicArray', () {
    final listEq = const ListEquality<int>().equals;

    test('empty array', () {
      final arr = LogicArray([0], 20);
      expect(arr.width, 0);
      expect(arr.elements.isEmpty, true);
      expect(arr.elementWidth, 0);
    });
    test('single-dim array', () {
      final dim = [5];
      const w = 16;
      final arr = LogicArray(dim, w);

      expect(listEq(arr.dimensions, dim), true);

      for (final element in arr.elements) {
        expect(element.width, w);
      }

      expect(arr.width, w * dim[0]);
      expect(arr.elementWidth, w);
    });
    test('many-dim array', () {
      final dim = [5, 8, 3];
      const w = 32;
      final arr = LogicArray(dim, w);

      expect(listEq(arr.dimensions, dim), true);

      // make sure we can access elements
      arr.elements[0].elements[2].elements[1];

      for (final element0 in arr.elements) {
        for (final element1 in element0.elements) {
          for (final element2 in element1.elements) {
            expect(element2.width, w);
          }
        }
      }
      expect(arr.width, w * dim.reduce((a, b) => a * b));
      expect(
          listEq((arr.elements[0] as LogicArray).dimensions,
              dim.getRange(1, dim.length).toList()),
          true);
      expect(arr.elementWidth, w);
    });
    test('no dim exception', () {
      //TODO
    });
  });

  group('logicarray passthrough', () {
    Future<void> testArrayPassthrough(SimpleLAPassthrough mod,
        {bool checkNoSwizzle = true, bool noSvSim = false}) async {
      await mod.build();

      const randWidth = 23;
      final rand = Random(1234);
      final values = List.generate(
          10,
          (index) => LogicValue.ofInt(rand.nextInt(1 << randWidth), randWidth)
              .replicate(mod.laOut.width ~/ randWidth + 1)
              .getRange(0, mod.laOut.width));

      final vectors = [
        for (final value in values) Vector({'laIn': value}, {'laOut': value})
      ];

      if (checkNoSwizzle) {
        expect(mod.generateSynth().contains('swizzle'), false);
      }

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors, buildOnly: noSvSim);
    }

    group('simple', () {
      test('single dimension', () async {
        final mod = SimpleLAPassthrough(LogicArray([3], 8));
        await testArrayPassthrough(mod);
      });

      test('2 dimensions', () async {
        final mod = SimpleLAPassthrough(LogicArray([3, 2], 8));
        await testArrayPassthrough(mod);
      });

      test('3 dimensions', () async {
        final mod = SimpleLAPassthrough(LogicArray([3, 2, 3], 8));
        await testArrayPassthrough(mod);
      });

      test('4 dimensions', () async {
        final mod = SimpleLAPassthrough(LogicArray([5, 4, 3, 2], 8));
        await testArrayPassthrough(mod);
      });

      test('1d, unpacked', () async {
        final mod =
            SimpleLAPassthrough(LogicArray([3], 8, numDimensionsUnpacked: 1));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(sv.contains(RegExp(r'\[7:0\]\s*laIn\s*\[2:0\]')), true);
        expect(sv.contains(RegExp(r'\[7:0\]\s*laOut\s*\[2:0\]')), true);
      });

      test('4d, half packed', () async {
        final mod = SimpleLAPassthrough(
            LogicArray([5, 4, 3, 2], 8, numDimensionsUnpacked: 2));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(
            sv.contains(RegExp(
                r'\[2:0\]\s*\[1:0\]\s*\[7:0\]\s*laIn\s*\[4:0\]\s*\[3:0\]')),
            true);
        expect(
            sv.contains(RegExp(
                r'\[2:0\]\s*\[1:0\]\s*\[7:0\]\s*laOut\s*\[4:0\]\s*\[3:0\]')),
            true);
      });
    });

    group('pack and unpack', () {
      test('1d', () async {
        final mod = PackAndUnpackPassthrough(LogicArray([3], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('3d', () async {
        final mod = PackAndUnpackPassthrough(LogicArray([5, 3, 2], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('3d unpacked', () async {
        final mod = PackAndUnpackPassthrough(
            LogicArray([5, 3, 2], 8, numDimensionsUnpacked: 2));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, checkNoSwizzle: false, noSvSim: true);
      });
    });

    group('pack and unpack with arrays', () {
      test('1d', () async {
        final mod = PackAndUnpackWithArraysPassthrough(LogicArray([3], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('2d', () async {
        final mod = PackAndUnpackWithArraysPassthrough(LogicArray([3, 2], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('3d', () async {
        final mod =
            PackAndUnpackWithArraysPassthrough(LogicArray([4, 3, 2], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('3d unpacked', () async {
        final mod = PackAndUnpackWithArraysPassthrough(
            LogicArray([4, 3, 2], 8, numDimensionsUnpacked: 2),
            intermediateUnpacked: 1);

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, checkNoSwizzle: false, noSvSim: true);
      });
    });

    group('change array dimensions around and back', () {
      test('3d', () async {
        final mod = RearrangeArraysPassthrough(LogicArray([4, 3, 2], 8));
        await testArrayPassthrough(mod);
      });

      test('3d unpacked', () async {
        final mod = RearrangeArraysPassthrough(
            LogicArray([4, 3, 2], 8, numDimensionsUnpacked: 2),
            intermediateUnpacked: 1);

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(sv.contains('logic [2:0][3:0][7:0] intermediate [1:0]'), true);
      });
    });
  });
}
