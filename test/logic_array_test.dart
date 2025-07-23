// Copyright (C) 2023-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array_test.dart
// Tests for LogicArray
//
// 2023 May 2
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

class SimpleLAPassthrough extends Module {
  Logic get laOut => output('laOut');
  SimpleLAPassthrough(
    LogicArray laIn, {
    List<int>? dimOverride,
    int? elemWidthOverride,
    int? numUnpackedOverride,
  }) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numUnpackedDimensions: numUnpackedOverride ?? laIn.numUnpackedDimensions,
    );

    addOutputArray(
          'laOut',
          dimensions: dimOverride ?? laIn.dimensions,
          elementWidth: elemWidthOverride ?? laIn.elementWidth,
          numUnpackedDimensions:
              numUnpackedOverride ?? laIn.numUnpackedDimensions,
        ) <=
        laIn;
  }
}

class RangeAndSliceArrModule extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  RangeAndSliceArrModule(LogicArray laIn) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: [3, 3, 3],
      elementWidth: 8,
    );

    addOutputArray(
      'laOut',
      dimensions: laIn.dimensions,
      elementWidth: laIn.elementWidth,
      numUnpackedDimensions: laIn.numUnpackedDimensions,
    );

    laOut.elements[0] <=
        [
          laIn.elements[0].getRange(16),
          laIn.elements[0].getRange(0, 16),
        ].swizzle();

    laOut.elements[1] <=
        [
          laIn.elements[1].slice(16, 3 * 3 * 8 - 1).reversed,
          laIn.elements[1].slice(15, 0),
        ].swizzle();

    laOut.elements[2] <=
        [
          laIn.elements[2].slice(-1, 0).getRange(3 * 3 * 8 ~/ 2),
          laIn.elements[2].getRange(-3 * 3 * 8).getRange(0, 3 * 3 * 8 ~/ 2),
        ].swizzle();
  }
}

class WithSetArrayModule extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  WithSetArrayModule(LogicArray laIn) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: [2, 2],
      elementWidth: 8,
    );

    addOutputArray(
      'laOut',
      dimensions: laIn.dimensions,
      elementWidth: laIn.elementWidth,
      numUnpackedDimensions: laIn.numUnpackedDimensions,
    );

    laOut <= laIn.withSet(8, laIn.elements[0].elements[1]);
  }
}

class WithSetArrayOffsetModule extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  WithSetArrayOffsetModule(LogicArray laIn) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: [2, 2],
      elementWidth: 8,
    );

    addOutputArray(
      'laOut',
      dimensions: laIn.dimensions,
      elementWidth: laIn.elementWidth,
      numUnpackedDimensions: laIn.numUnpackedDimensions,
    );

    laOut <= laIn.withSet(3 + 16, laIn.elements[1].getRange(3, 3 + 9));
  }
}

enum LADir { laIn, laOut }

class LAPassthroughIntf extends Interface<LADir> {
  final List<int> dimensions;
  final int elementWidth;
  final int numUnpackedDimensions;

  Logic get laIn => port('laIn');
  Logic get laOut => port('laOut');

  LAPassthroughIntf({
    required this.dimensions,
    required this.elementWidth,
    required this.numUnpackedDimensions,
  }) {
    setPorts([
      LogicArray.port('laIn', dimensions, elementWidth, numUnpackedDimensions)
    ], [
      LADir.laIn
    ]);

    setPorts([
      LogicArray.port('laOut', dimensions, elementWidth, numUnpackedDimensions)
    ], [
      LADir.laOut
    ]);
  }

  LAPassthroughIntf.clone(LAPassthroughIntf other)
      : this(
          dimensions: other.dimensions,
          elementWidth: other.elementWidth,
          numUnpackedDimensions: other.numUnpackedDimensions,
        );

  @override
  LAPassthroughIntf clone() => LAPassthroughIntf(
        dimensions: dimensions,
        elementWidth: elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
      );
}

class LAPassthroughWithIntf extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');
  LAPassthroughWithIntf(
    LAPassthroughIntf intf,
  ) {
    intf = LAPassthroughIntf.clone(intf)
      ..connectIO(this, intf,
          inputTags: {LADir.laIn}, outputTags: {LADir.laOut});

    intf.laOut <= intf.laIn;
  }
}

class SimpleLAPassthroughLogic extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');
  SimpleLAPassthroughLogic(
    Logic laIn, {
    required List<int> dimensions,
    required int elementWidth,
    required int numUnpackedDimensions,
  }) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: dimensions,
      elementWidth: elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
    );

    addOutputArray(
          'laOut',
          dimensions: dimensions,
          elementWidth: elementWidth,
          numUnpackedDimensions: numUnpackedDimensions,
        ) <=
        laIn;
  }
}

class PackAndUnpackPassthrough extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  PackAndUnpackPassthrough(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    final intermediate = Logic(name: 'intermediate', width: laIn.width);

    intermediate <= laIn;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        intermediate;
  }
}

class PackAndUnpackWithArraysPassthrough extends Module
    implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  PackAndUnpackWithArraysPassthrough(LogicArray laIn,
      {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    final intermediate1 = Logic(name: 'intermediate1', width: laIn.width);
    final intermediate3 = Logic(name: 'intermediate2', width: laIn.width);

    // unpack with reversed dimensions
    final intermediate2 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate2', numUnpackedDimensions: intermediateUnpacked);

    intermediate1 <= laIn;
    intermediate2 <= intermediate1;
    intermediate3 <= intermediate2;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        intermediate3;
  }
}

class RearrangeArraysPassthrough extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  RearrangeArraysPassthrough(LogicArray laIn, {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    // rearrange with reversed dimensions
    final intermediate = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numUnpackedDimensions: intermediateUnpacked);

    intermediate <= laIn;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        intermediate;
  }
}

class ArrayNameConflicts extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  ArrayNameConflicts(LogicArray laIn, {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    final intermediate1 = Logic(name: 'intermediate', width: laIn.width);
    final intermediate3 = Logic(name: 'intermediate', width: laIn.width);
    final intermediate5 = Logic(name: 'intermediate', width: laIn.width);

    // unpack with reversed dimensions
    final intermediate2 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numUnpackedDimensions: intermediateUnpacked);

    final intermediate4 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numUnpackedDimensions: intermediateUnpacked);

    intermediate1 <= laIn;
    intermediate2 <= intermediate1;
    intermediate3 <= intermediate2;
    intermediate4 <= intermediate3;
    intermediate5 <= intermediate4;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        intermediate5;
  }
}

class SimpleArraysAndHierarchy extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  SimpleArraysAndHierarchy(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    final intermediate = SimpleLAPassthrough(laIn).laOut;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        intermediate;
  }
}

class FancyArraysAndHierarchy extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  FancyArraysAndHierarchy(LogicArray laIn, {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numUnpackedDimensions: laIn.numUnpackedDimensions);

    final invertedLaIn = LogicArray(laIn.dimensions, laIn.elementWidth,
        numUnpackedDimensions: intermediateUnpacked)
      ..gets(~laIn);

    final x1 = SimpleLAPassthrough(laIn).laOut;
    final x2 = SimpleLAPassthrough(laIn).laOut;
    final x3 = SimpleLAPassthrough(invertedLaIn).laOut;
    final x4 = SimpleLAPassthrough(invertedLaIn).laOut;

    final y1 = ~(x1 ^ x3);
    final y2 = ~(x2 ^ x4);

    final z1 = laIn ^ y1;
    final z2 = y2 ^ laIn;

    final same = z1 & z2;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numUnpackedDimensions: laIn.numUnpackedDimensions) <=
        same;
  }
}

class ConstantAssignmentArrayModule extends Module {
  Logic get laOut => output('laOut');

  ConstantAssignmentArrayModule(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: [3, 3, 3, 3],
        numUnpackedDimensions: laIn.numUnpackedDimensions,
        elementWidth: 8);

    addOutputArray('laOut',
        dimensions: laIn.dimensions,
        numUnpackedDimensions: laIn.numUnpackedDimensions,
        elementWidth: laIn.elementWidth);

    laOut.elements[1] <=
        Const([for (var i = 0; i < 3 * 3 * 3; i++) LogicValue.ofInt(i, 8)]
            .rswizzle());
    laOut.elements[2].elements[1] <=
        (Logic(width: 3 * 3 * 8)..gets(Const(0, width: 3 * 3 * 8)));
    laOut.elements[2].elements[2].elements[1] <=
        Const(1, width: 3 * 8, fill: true);
    laOut.elements[2].elements[2].elements[2].elements[1] <= Const(0, width: 8);
  }
}

class CondAssignArray extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');
  CondAssignArray(
    LogicArray laIn, {
    List<int>? dimOverride,
    int? elemWidthOverride,
    int? numUnpackedOverride,
  }) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numUnpackedDimensions: numUnpackedOverride ?? laIn.numUnpackedDimensions,
    );

    final laOut = addOutputArray(
      'laOut',
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numUnpackedDimensions: numUnpackedOverride ?? laIn.numUnpackedDimensions,
    );

    Combinational([laOut < laIn]);
  }
}

class CondCompArray extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');
  CondCompArray(
    LogicArray laIn, {
    List<int>? dimOverride,
    int? elemWidthOverride,
    int? numUnpackedOverride,
  })  : assert(laIn.dimensions.length == 1, 'test assumes 1x1 array'),
        assert(laIn.width == 1, 'test assumes 1x1 array') {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numUnpackedDimensions: numUnpackedOverride ?? laIn.numUnpackedDimensions,
    );

    final laOut = addOutputArray(
      'laOut',
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numUnpackedDimensions: numUnpackedOverride ?? laIn.numUnpackedDimensions,
    );

    Combinational([
      If(
        laIn,
        then: [laOut < laIn],
        orElse: [
          Case(laIn, [
            CaseItem(Const(0), [laOut < laIn]),
            CaseItem(Const(1), [laOut < ~laIn]),
          ])
        ],
      ),
    ]);
  }
}

class IndexBitOfArrayModule extends Module {
  IndexBitOfArrayModule() {
    final o = LogicArray([2, 2, 2], 8);
    o <= Const(LogicValue.ofString('10').replicate(2 * 2 * 8));
    addOutput('o0') <= o[0];
    addOutput('o3') <= o[3];
  }
}

class AssignSubsetModule extends Module {
  AssignSubsetModule(LogicArray updatedSubset,
      {int? start, bool? isError = false}) {
    final dim = ((isError != null && isError) ? 10 : 5);
    updatedSubset = addInputArray('inputLogicArray', updatedSubset,
        dimensions: [dim], elementWidth: 3);

    final o =
        addOutputArray('outputLogicArray', dimensions: [10], elementWidth: 3);
    final error = addOutput('errorBit');
    try {
      if (start != null) {
        o.assignSubset(updatedSubset.elements, start: start);
      } else {
        o.assignSubset(updatedSubset.elements);
      }
    } on SignalWidthMismatchException {
      error <= Const(1);
    }
  }
}

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

    test('empty multi-dim array', () {
      final arr = LogicArray([5, 2, 0, 3], 6);
      expect(arr.width, 0);
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
      expect(
          () => LogicArray([], 3), throwsA(isA<LogicConstructionException>()));
    });

    test('overly unpacking exception', () {
      expect(() => LogicArray([1, 2, 3], 4, numUnpackedDimensions: 4),
          throwsA(isA<LogicConstructionException>()));
    });

    test('unpacked dims get passed down', () {
      final arr = LogicArray([1, 2, 3], 4, numUnpackedDimensions: 2);
      expect(arr.numUnpackedDimensions, 2);
      expect((arr.elements[0] as LogicArray).numUnpackedDimensions, 1);
      expect(
          (arr.elements[0].elements[0] as LogicArray).numUnpackedDimensions, 0);
    });
  });

  group('access logicarray', () {
    test('slice one bit of 1d array', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(9, 9);
      expect(slice.width, 1);
      la.elements[1].put(bin('00000010'));
      expect(slice.value.toInt(), 1);
    });

    test('slice 2 bits of one element of 1d array', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(10, 9);
      expect(slice.width, 2);
      la.elements[1].put(bin('00000110'));
      expect(slice.value.toInt(), bin('11'));
    });

    test('slice 2 bits spanning two elements of 1d array', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(8, 7);
      expect(slice.width, 2);
      la.elements[1].put(1, fill: true);
      la.elements[0].put(0, fill: true);
      expect(slice.value.toInt(), bin('10'));
    });

    test('slice 2 bits spanning 2 arrays of 2d array', () async {
      final la = LogicArray([3, 2], 8);
      final slice = la.slice(16, 15);
      expect(slice.width, 2);
      la.elements[1].elements[0].put(1, fill: true);
      la.elements[0].elements[1].put(0, fill: true);
      expect(slice.value.toInt(), bin('10'));
    });

    test('slice more than one element of array', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(19, 4);
      expect(slice.width, 16);
      la.elements[2].put(LogicValue.x);
      la.elements[1].put(0);
      la.elements[0].put(1, fill: true);
      expect(slice.value, LogicValue.of('xxxx000000001111'));
    });

    test('slice more than one element of array at the edges', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(16, 7);
      expect(slice.width, 10);
      la.elements[2].put(LogicValue.x);
      la.elements[1].put(0);
      la.elements[0].put(1, fill: true);
      expect(slice.value, LogicValue.of('x000000001'));
    });

    test('slice exactly one element of array', () async {
      final la = LogicArray([3], 8);
      final slice = la.slice(15, 8);
      expect(slice.width, 8);
      la.elements[1].put(1, fill: true);
      expect(slice.value, LogicValue.of('11111111'));
    });
  });

  group('logicarray passthrough', () {
    Future<void> testArrayPassthrough(SimpleLAPassthrough mod,
        {bool checkNoSwizzle = true,
        bool noSvSim = false,
        bool noIverilog = false,
        bool dontDeleteTmpFiles = false}) async {
      await mod.build();

      const randWidth = 23;
      final rand = Random(1234);
      final values = List.generate(
          10,
          (index) =>
              LogicValue.ofInt(rand.nextInt(oneSllBy(randWidth)), randWidth)
                  .replicate(mod.laOut.width ~/ randWidth + 1)
                  .getRange(0, mod.laOut.width));

      final vectors = [
        for (final value in values) Vector({'laIn': value}, {'laOut': value})
      ];

      if (checkNoSwizzle) {
        expect(mod.generateSynth().contains('swizzle'), false,
            reason: 'Expected no swizzles but found one.');
      }

      await SimCompare.checkFunctionalVector(mod, vectors);
      if (!noIverilog) {
        SimCompare.checkIverilogVector(mod, vectors,
            buildOnly: noSvSim, dontDeleteTmpFiles: dontDeleteTmpFiles);
      }
    }

    group('simple', () {
      test('single dimension', () async {
        final mod = SimpleLAPassthrough(LogicArray([3], 8));
        await testArrayPassthrough(mod);
      });

      test('single element', () async {
        final mod = SimpleLAPassthrough(LogicArray([1], 8));
        await testArrayPassthrough(mod);
      });

      test('array of bits', () async {
        final mod = SimpleLAPassthrough(LogicArray([8], 1));
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
            SimpleLAPassthrough(LogicArray([3], 8, numUnpackedDimensions: 1));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(sv.contains(RegExp(r'\[7:0\]\s*laIn\s*\[2:0\]')), true);
        expect(sv.contains(RegExp(r'\[7:0\]\s*laOut\s*\[2:0\]')), true);
      });

      test('single element, unpacked', () async {
        final mod =
            SimpleLAPassthrough(LogicArray([1], 8, numUnpackedDimensions: 1));
        await testArrayPassthrough(mod, noSvSim: true, noIverilog: true);
      });

      test('4d, half packed', () async {
        final mod = SimpleLAPassthrough(
            LogicArray([5, 4, 3, 2], 8, numUnpackedDimensions: 2));

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

      test('sub-array', () async {
        final superArray = LogicArray([4, 3, 2], 8);
        final subArray = superArray.elements[0] as LogicArray;
        final mod = SimpleLAPassthrough(subArray);
        await testArrayPassthrough(mod);
      });

      test('3 dimensions with interface', () async {
        final mod = LAPassthroughWithIntf(LAPassthroughIntf(
          dimensions: [3, 2, 3],
          elementWidth: 8,
          numUnpackedDimensions: 0,
        ));

        await testArrayPassthrough(mod);

        // ensure ports with interface are still an array
        final sv = mod.generateSynth();
        expect(sv, contains('input logic [2:0][1:0][2:0][7:0] laIn'));
        expect(sv, contains('output logic [2:0][1:0][2:0][7:0] laOut'));
      });

      test('3 dimensions with interface and unpacked', () async {
        final mod = LAPassthroughWithIntf(LAPassthroughIntf(
          dimensions: [3, 2, 3],
          elementWidth: 8,
          numUnpackedDimensions: 1,
        ));

        await testArrayPassthrough(mod, noSvSim: true);

        // ensure ports with interface are still an array
        final sv = mod.generateSynth();
        expect(sv, contains('input logic [1:0][2:0][7:0] laIn [2:0]'));
        expect(sv, contains('output logic [1:0][2:0][7:0] laOut [2:0]'));
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
            LogicArray([5, 3, 2], 8, numUnpackedDimensions: 2));

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
            LogicArray([4, 3, 2], 8, numUnpackedDimensions: 2),
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
            LogicArray([4, 3, 2], 8, numUnpackedDimensions: 2),
            intermediateUnpacked: 1);

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(sv.contains('logic [2:0][3:0][7:0] intermediate [1:0]'), true);
      });
    });

    group('different port and input widths', () {
      test('array param mismatch', () async {
        final i = LogicArray([3, 2], 8, numUnpackedDimensions: 1);
        final o = LogicArray([3, 2], 8, numUnpackedDimensions: 1);
        final mod = SimpleLAPassthrough(
          i,
          dimOverride: [1, 3],
          elemWidthOverride: 16,
          numUnpackedOverride: 0,
        );
        o <= mod.laOut;
        await testArrayPassthrough(mod);
      });

      test('logic into array', () async {
        final i = Logic(width: 3 * 2 * 8);
        final o = Logic(width: 3 * 2 * 8);
        final mod = SimpleLAPassthroughLogic(
          i,
          dimensions: [1, 3],
          elementWidth: 16,
          numUnpackedDimensions: 0,
        );
        o <= mod.laOut;
        await testArrayPassthrough(mod);
      });
    });

    group('name collisions', () {
      test('3d', () async {
        final mod = ArrayNameConflicts(LogicArray([4, 3, 2], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);
      });

      test('3d unpacked', () async {
        final mod = ArrayNameConflicts(
            LogicArray([4, 3, 2], 8, numUnpackedDimensions: 2),
            intermediateUnpacked: 1);

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, checkNoSwizzle: false, noSvSim: true);
      });
    });

    group('simple hierarchy', () {
      test('3d', () async {
        final mod = SimpleArraysAndHierarchy(LogicArray([2], 8));
        await testArrayPassthrough(mod);

        expect(mod.generateSynth(),
            contains('SimpleLAPassthrough  unnamed_module'));
      });

      test('3d unpacked', () async {
        final mod = SimpleArraysAndHierarchy(
            LogicArray([4, 3, 2], 8, numUnpackedDimensions: 2));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        expect(mod.generateSynth(), contains('SimpleLAPassthrough'));
      });
    });

    group('fancy hierarchy', () {
      test('3d', () async {
        final mod = FancyArraysAndHierarchy(LogicArray([4, 3, 2], 8));
        await testArrayPassthrough(mod, checkNoSwizzle: false);

        // make sure the 4th one is there (since we expect 4)
        expect(mod.generateSynth(),
            contains('SimpleLAPassthrough  unnamed_module_2'));
      });

      test('3d unpacked', () async {
        final mod = FancyArraysAndHierarchy(
            LogicArray([4, 3, 2], 8, numUnpackedDimensions: 2),
            intermediateUnpacked: 1);

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, checkNoSwizzle: false, noSvSim: true);
      });
    });

    group('conditionals', () {
      test('3 dimensions conditional assignment', () async {
        final mod = CondAssignArray(LogicArray([3, 2, 3], 8));
        await testArrayPassthrough(mod);
      });

      test('1x1 expressions in if and case', () async {
        final mod = CondCompArray(LogicArray([1], 1));
        await testArrayPassthrough(mod);
      });
    });

    test('slice and dice', () async {
      final mod = RangeAndSliceArrModule(LogicArray([3, 3, 3], 8));
      await testArrayPassthrough(mod, checkNoSwizzle: false);
    });

    test('withset', () async {
      final mod = WithSetArrayModule(LogicArray([2, 2], 8));
      await testArrayPassthrough(mod);
    });

    test('withset offset', () async {
      final mod = WithSetArrayOffsetModule(LogicArray([2, 2], 8));
      await testArrayPassthrough(mod, checkNoSwizzle: false);

      final sv = mod.generateSynth();

      // make sure we're reassigning both times it overlaps!
      expect(
          RegExp(r'assign laOut\[1\].*=.*swizzled').allMatches(sv).length, 2);
    });
  });

  group('array constant assignments', () {
    Future<void> testArrayConstantAssignments(
        {required int numUnpackedDimensions, bool doSvSim = true}) async {
      final mod = ConstantAssignmentArrayModule(LogicArray([3, 3, 3, 3], 8,
          numUnpackedDimensions: numUnpackedDimensions));
      await mod.build();

      final a = <LogicValue>[];
      var iIdx = 0;
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          for (var k = 0; k < 3; k++) {
            for (var l = 0; l < 3; l++) {
              if (i == 1) {
                a.add(LogicValue.ofInt(iIdx, 8));
                iIdx++;
              } else if (i == 2 && j == 1) {
                a.add(LogicValue.filled(8, LogicValue.zero));
              } else if (i == 2 && j == 2 && k == 1) {
                a.add(LogicValue.filled(8, LogicValue.one));
              } else if (i == 2 && j == 2 && k == 2 && l == 1) {
                a.add(LogicValue.filled(8, LogicValue.zero));
              } else {
                a.add(LogicValue.filled(8, LogicValue.z));
              }
            }
          }
        }
      }
      final vectors = [
        Vector({'laIn': 0}, {'laOut': a.rswizzle()})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors, buildOnly: !doSvSim);
    }

    test('with packed only', () async {
      await testArrayConstantAssignments(numUnpackedDimensions: 0);
    });

    test('with unpacked also', () async {
      // unpacked array assignment not fully supported in iverilog
      await testArrayConstantAssignments(
          numUnpackedDimensions: 2, doSvSim: false);
    });

    test('indexing single bit of array', () async {
      final mod = IndexBitOfArrayModule();
      await mod.build();

      final vectors = [
        Vector({}, {'o0': 0, 'o3': 1})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('assign subset of logic array without mentioning start', () async {
      final updatedSubset = LogicArray([5], 3, name: 'updatedSubset');
      final mod = AssignSubsetModule(updatedSubset);
      await mod.build();

      final vectors = [
        Vector({'inputLogicArray': 0},
            {'outputLogicArray': LogicValue.ofString(('z' * 15) + ('0' * 15))}),
        Vector({'inputLogicArray': bin('101' * 5)},
            {'outputLogicArray': LogicValue.ofString(('z' * 15) + ('101' * 5))})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('assign subset of logic array with mentioning start', () async {
      final updatedSubset = LogicArray([5], 3, name: 'updatedSubset');
      final mod = AssignSubsetModule(updatedSubset, start: 3);
      await mod.build();

      final vectors = [
        Vector({
          'inputLogicArray': 0
        }, {
          'outputLogicArray':
              LogicValue.ofString(('z' * 3 * 2) + ('0' * 3 * 5) + ('z' * 3 * 3))
        }),
        Vector({
          'inputLogicArray': bin('101' * 5)
        }, {
          'outputLogicArray':
              LogicValue.ofString(('z' * 3 * 2) + ('101' * 5) + ('z' * 3 * 3))
        }),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('error in assign subset of logic array', () async {
      final updatedSubset = LogicArray([10], 3, name: 'updatedSubset');
      final mod = AssignSubsetModule(updatedSubset, start: 3, isError: true);
      await mod.build();

      final vectors = [
        Vector({'inputLogicArray': bin('101' * 10)}, {'errorBit': 1})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('array clone', () {
    for (final isNet in [true, false]) {
      test('isNet = $isNet', () {
        final la = (isNet ? LogicArray.net : LogicArray.new)(
          [3, 2, 4],
          8,
          numUnpackedDimensions: 1,
          name: 'myarray',
          naming: Naming.reserved,
        );
        final clone = la.clone();
        expect(la.dimensions, clone.dimensions);
        expect(la.elementWidth, clone.elementWidth);
        expect(la.numUnpackedDimensions, clone.numUnpackedDimensions);
        expect(la.width, clone.width);
        expect(la.elements.length, clone.elements.length);
        for (var i = 0; i < la.elements.length; i++) {
          expect(la.elements[i].width, clone.elements[i].width);
        }
        expect(la.name, clone.name);
        expect(la.isNet, clone.isNet);
        expect(clone.elements[0].elements[1].isNet, isNet);
        expect(
            clone.elements[1].elements[1].elements[1] is LogicArray, isFalse);
        expect(clone.elements[1].elements[1].elements[1].isNet, isNet);
      });
    }
  });
}
