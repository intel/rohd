// Copyright (C) 2023 Intel Corporation
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
import 'package:rohd/src/exceptions/exceptions.dart';
import 'package:rohd/src/utilities/simcompare.dart';
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
      numDimensionsUnpacked: numUnpackedOverride ?? laIn.numDimensionsUnpacked,
    );

    addOutputArray(
          'laOut',
          dimensions: dimOverride ?? laIn.dimensions,
          elementWidth: elemWidthOverride ?? laIn.elementWidth,
          numDimensionsUnpacked:
              numUnpackedOverride ?? laIn.numDimensionsUnpacked,
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
      numDimensionsUnpacked: laIn.numDimensionsUnpacked,
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

class WithSetArray extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  WithSetArray(LogicArray laIn) {
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
      numDimensionsUnpacked: laIn.numDimensionsUnpacked,
    );

    laOut <= laIn.withSet(8, laIn.elements[0].elements[1]);
  }
}

enum LADir { laIn, laOut }

class LAPassthroughIntf extends Interface<LADir> {
  final List<int> dimensions;
  final int elementWidth;
  final int numDimensionsUnpacked;

  Logic get laIn => port('laIn');
  Logic get laOut => port('laOut');

  LAPassthroughIntf({
    required this.dimensions,
    required this.elementWidth,
    required this.numDimensionsUnpacked,
  }) {
    setPorts([
      LogicArray.port('laIn', dimensions, elementWidth, numDimensionsUnpacked)
    ], [
      LADir.laIn
    ]);

    setPorts([
      LogicArray.port('laOut', dimensions, elementWidth, numDimensionsUnpacked)
    ], [
      LADir.laOut
    ]);
  }

  LAPassthroughIntf.clone(LAPassthroughIntf other)
      : this(
          dimensions: other.dimensions,
          elementWidth: other.elementWidth,
          numDimensionsUnpacked: other.numDimensionsUnpacked,
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
    required int numDimensionsUnpacked,
  }) {
    laIn = addInputArray(
      'laIn',
      laIn,
      dimensions: dimensions,
      elementWidth: elementWidth,
      numDimensionsUnpacked: numDimensionsUnpacked,
    );

    addOutputArray(
          'laOut',
          dimensions: dimensions,
          elementWidth: elementWidth,
          numDimensionsUnpacked: numDimensionsUnpacked,
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
  @override
  Logic get laOut => output('laOut');

  PackAndUnpackWithArraysPassthrough(LogicArray laIn,
      {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final intermediate1 = Logic(name: 'intermediate1', width: laIn.width);
    final intermediate3 = Logic(name: 'intermediate2', width: laIn.width);

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
  @override
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

class ArrayNameConflicts extends Module implements SimpleLAPassthrough {
  @override
  Logic get laOut => output('laOut');

  ArrayNameConflicts(LogicArray laIn, {int intermediateUnpacked = 0}) {
    laIn = addInputArray('laIn', laIn,
        dimensions: laIn.dimensions,
        elementWidth: laIn.elementWidth,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final intermediate1 = Logic(name: 'intermediate', width: laIn.width);
    final intermediate3 = Logic(name: 'intermediate', width: laIn.width);
    final intermediate5 = Logic(name: 'intermediate', width: laIn.width);

    // unpack with reversed dimensions
    final intermediate2 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numDimensionsUnpacked: intermediateUnpacked);

    final intermediate4 = LogicArray(
        laIn.dimensions.reversed.toList(), laIn.elementWidth,
        name: 'intermediate', numDimensionsUnpacked: intermediateUnpacked);

    intermediate1 <= laIn;
    intermediate2 <= intermediate1;
    intermediate3 <= intermediate2;
    intermediate4 <= intermediate3;
    intermediate5 <= intermediate4;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
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
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final intermediate = SimpleLAPassthrough(laIn).laOut;

    addOutputArray('laOut',
            dimensions: laIn.dimensions,
            elementWidth: laIn.elementWidth,
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
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
        numDimensionsUnpacked: laIn.numDimensionsUnpacked);

    final invertedLaIn = LogicArray(laIn.dimensions, laIn.elementWidth,
        numDimensionsUnpacked: intermediateUnpacked)
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
            numDimensionsUnpacked: laIn.numDimensionsUnpacked) <=
        same;
  }
}

class ConstantAssignmentArrayModule extends Module {
  Logic get laOut => output('laOut');

  ConstantAssignmentArrayModule(LogicArray laIn) {
    laIn = addInputArray('laIn', laIn,
        dimensions: [3, 3, 3, 3],
        numDimensionsUnpacked: laIn.numDimensionsUnpacked,
        elementWidth: 8);

    addOutputArray('laOut',
        dimensions: laIn.dimensions,
        numDimensionsUnpacked: laIn.numDimensionsUnpacked,
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
      numDimensionsUnpacked: numUnpackedOverride ?? laIn.numDimensionsUnpacked,
    );

    final laOut = addOutputArray(
      'laOut',
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numDimensionsUnpacked: numUnpackedOverride ?? laIn.numDimensionsUnpacked,
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
      numDimensionsUnpacked: numUnpackedOverride ?? laIn.numDimensionsUnpacked,
    );

    final laOut = addOutputArray(
      'laOut',
      dimensions: dimOverride ?? laIn.dimensions,
      elementWidth: elemWidthOverride ?? laIn.elementWidth,
      numDimensionsUnpacked: numUnpackedOverride ?? laIn.numDimensionsUnpacked,
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
      expect(() => LogicArray([1, 2, 3], 4, numDimensionsUnpacked: 4),
          throwsA(isA<LogicConstructionException>()));
    });

    test('unpacked dims get passed down', () {
      final arr = LogicArray([1, 2, 3], 4, numDimensionsUnpacked: 2);
      expect(arr.numDimensionsUnpacked, 2);
      expect((arr.elements[0] as LogicArray).numDimensionsUnpacked, 1);
      expect(
          (arr.elements[0].elements[0] as LogicArray).numDimensionsUnpacked, 0);
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
          (index) => LogicValue.ofInt(rand.nextInt(1 << randWidth), randWidth)
              .replicate(mod.laOut.width ~/ randWidth + 1)
              .getRange(0, mod.laOut.width));

      final vectors = [
        for (final value in values) Vector({'laIn': value}, {'laOut': value})
      ];

      if (checkNoSwizzle) {
        expect(mod.generateSynth().contains('swizzle'), false,
            reason: 'Expected no swizzles but found one.');
      }

      // await SimCompare.checkFunctionalVector(mod, vectors);
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
            SimpleLAPassthrough(LogicArray([3], 8, numDimensionsUnpacked: 1));

        // unpacked array assignment not fully supported in iverilog
        await testArrayPassthrough(mod, noSvSim: true);

        final sv = mod.generateSynth();
        expect(sv.contains(RegExp(r'\[7:0\]\s*laIn\s*\[2:0\]')), true);
        expect(sv.contains(RegExp(r'\[7:0\]\s*laOut\s*\[2:0\]')), true);
      });

      test('single element, unpacked', () async {
        final mod =
            SimpleLAPassthrough(LogicArray([1], 8, numDimensionsUnpacked: 1));
        await testArrayPassthrough(mod, noSvSim: true, noIverilog: true);
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
          numDimensionsUnpacked: 0,
        ));
        await testArrayPassthrough(mod);
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

    group('different port and input widths', () {
      test('array param mismatch', () async {
        final i = LogicArray([3, 2], 8, numDimensionsUnpacked: 1);
        final o = LogicArray([3, 2], 8, numDimensionsUnpacked: 1);
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
          numDimensionsUnpacked: 0,
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
            LogicArray([4, 3, 2], 8, numDimensionsUnpacked: 2),
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
            LogicArray([4, 3, 2], 8, numDimensionsUnpacked: 2));

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
            LogicArray([4, 3, 2], 8, numDimensionsUnpacked: 2),
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
      final mod = WithSetArray(LogicArray([2, 2], 8));
      await testArrayPassthrough(mod);
    });
  });

  group('array constant assignments', () {
    Future<void> testArrayConstantAssignments(
        {required int numDimensionsUnpacked, bool doSvSim = true}) async {
      final mod = ConstantAssignmentArrayModule(LogicArray([3, 3, 3, 3], 8,
          numDimensionsUnpacked: numDimensionsUnpacked));
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
      await testArrayConstantAssignments(numDimensionsUnpacked: 0);
    });

    test('with unpacked also', () async {
      // unpacked array assignment not fully supported in iverilog
      await testArrayConstantAssignments(
          numDimensionsUnpacked: 2, doSvSim: false);
    });
  });
}
