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
        dimensions: laIn.dimensions, elementWidth: laIn.elementWidth);

    addOutputArray('laOut',
            dimensions: laIn.dimensions, elementWidth: laIn.elementWidth) <=
        laIn;

    //TODO: add some more interesting logic
  }
}

//TODO: test internal array signals as well
//TODO: test module hierarchy

void main() {
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

  group('simple logicarray passthrough module', () {
    Future<void> testArrayPassthrough(SimpleLAPassthrough mod) async {
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

      //TODO: test we don't generate extraneous packed things in verilog

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors, dontDeleteTmpFiles: true);
    }

    test('single dimension', () async {
      final mod = SimpleLAPassthrough(LogicArray([3], 8));
      await testArrayPassthrough(mod);
      // await mod.build();
      //

      // File('tmp_simple_la_mod.sv').writeAsStringSync(mod.generateSynth());
    });

    test('2 dimensions', () async {
      final mod = SimpleLAPassthrough(LogicArray([3, 2], 8));
      await mod.build();
      //TODO: test we don't generate extraneous packed things

      File('tmp_simple_la_mod_2dim.sv').writeAsStringSync(mod.generateSynth());
    });

    test('3 dimensions', () async {
      final mod = SimpleLAPassthrough(LogicArray([3, 2, 3], 8));
      await mod.build();
      //TODO: test we don't generate extraneous packed things

      File('tmp_simple_la_mod_3dim.sv').writeAsStringSync(mod.generateSynth());
    });
  });
}
