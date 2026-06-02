// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// array_collapsing_test.dart
// Tests for array collapsing
//
// 2024 June 5
// Author: Shankar Sharma <shankar.sharma@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import 'logic_array_test.dart';

class ArrayModule extends Module {
  ArrayModule(LogicArray a) {
    final inpA = addInputArray('a', a, dimensions: a.dimensions);
    addOutputArray('b', dimensions: a.dimensions) <= inpA;

    final inoutA = addInOutArray('c', a, dimensions: a.dimensions);
    addOutputArray('d', dimensions: [a.dimensions.last]) <=
        inoutA.elements.first;
  }
}

class ArrayTopMod extends Module {
  ArrayTopMod(Logic clk) {
    clk = addInput('clk', clk);

    final intermediate =
        LogicArray([4], 1, name: 'asdf', naming: Naming.mergeable);
    final arrOut = ArraySubModOut(clk).arrOut;
    for (var i = 0; i < intermediate.width; i++) {
      final idx = (i + 1) % intermediate.width;
      intermediate.elements[idx] <= arrOut.elements[idx];
    }
    ArraySubModIn(clk, intermediate);
  }
}

class ArraySubModIn extends Module {
  ArraySubModIn(Logic clk, LogicArray inp) {
    clk = addInput('clk', clk);
    addInputArray('inp', inp, dimensions: [4]);
  }
}

class ArraySubModOut extends Module {
  LogicArray get arrOut => output('arrOut') as LogicArray;
  ArraySubModOut(Logic clk) {
    clk = addInput('clk', clk);
    addOutputArray('arrOut', dimensions: [4]);
  }
}

class ArrayWithShuffledAssignment extends Module {
  ArrayWithShuffledAssignment(LogicArray a) {
    final inpA = addInputArray('a', a, dimensions: a.dimensions);
    final outB = addOutputArray('b', dimensions: a.dimensions);

    for (var i = 0; i < a.dimensions.first; i++) {
      outB.elements[i] <= inpA.elements[a.dimensions.first - i - 1];
    }
  }
}

/// Inverts a bus of the given `width`.
class InverterMod extends Module {
  Logic get o => output('o');
  InverterMod(Logic i, {int width = 1}) {
    i = addInput('i', i, width: width);
    addOutput('o', width: width) <= ~i;
  }
}

/// Bidirectionally connects two nets of the given `width`.
class NetPassthrough extends Module {
  NetPassthrough(Logic x, Logic y, {int width = 1}) {
    x = addInOut('x', x, width: width);
    y = addInOut('y', y, width: width);
    x <= y;
  }
}

/// A flat input bus blasted into an array of `dimensions`/`elementWidth`, each
/// leaf element feeding an [InverterMod] (computing `~a`).  The intermediate
/// array should disappear and the submodule ports should reference the input
/// bits directly.  When `reversed`, leaves are consumed in reverse order.
class ArrayElementFanout extends Module {
  ArrayElementFanout(
    Logic a, {
    List<int> dimensions = const [4],
    int elementWidth = 1,
    bool reversed = false,
  }) {
    final total = dimensions.reduce((x, y) => x * y) * elementWidth;
    a = addInput('a', a, width: total);
    final arr = LogicArray(dimensions, elementWidth,
        name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final leaves = arr.leafElements;
    final results = <Logic>[];
    for (var i = 0; i < leaves.length; i++) {
      final srcIdx = reversed ? leaves.length - 1 - i : i;
      results.add(InverterMod(leaves[srcIdx], width: elementWidth).o);
    }

    addOutput('y', width: total) <= results.rswizzle();
  }
}

/// Net version of [ArrayElementFanout]: a flat inout bus blasted into a net
/// array whose leaves bidirectionally connect (via [NetPassthrough]) to an
/// output bus.  The intermediate array and its `net_connect`s should disappear.
class NetArrayElementFanout extends Module {
  NetArrayElementFanout(
    LogicNet a,
    LogicNet b, {
    List<int> dimensions = const [4],
    int elementWidth = 1,
  }) {
    final total = dimensions.reduce((x, y) => x * y) * elementWidth;
    a = addInOut('a', a, width: total);
    b = addInOut('b', b, width: total);
    final arr = LogicArray.net(dimensions, elementWidth,
        name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final leaves = arr.leafElements;
    for (var i = 0; i < leaves.length; i++) {
      NetPassthrough(
          leaves[i], b.getRange(i * elementWidth, (i + 1) * elementWidth),
          width: elementWidth);
    }
  }
}

/// An array where only some leaf elements are driven (the first and last are
/// left undriven), with the whole array reconstructed via a swizzle.  This must
/// NOT be inlined away (partial inlining would change `x`/`z` behavior of the
/// undriven bits).
class PartiallyDrivenArray extends Module {
  PartiallyDrivenArray(Logic a, {List<int> dimensions = const [4]}) {
    final total = dimensions.reduce((x, y) => x * y);
    a = addInput('a', a, width: total - 2);
    final arr =
        LogicArray(dimensions, 1, name: 'arr', naming: Naming.mergeable);

    final leaves = arr.leafElements;
    // drive everything except the first and last leaf
    for (var i = 1; i < leaves.length - 1; i++) {
      leaves[i] <= a[i - 1];
    }

    addOutput('y', width: total) <= leaves.rswizzle();
  }
}

/// The array's leaves feed submodules, but the whole array is ALSO consumed as
/// an aggregate (assigned to an output array).  Because of the aggregate use,
/// the elements must NOT be inlined and the array must remain declared.
class ArrayElementsWithAggregateUse extends Module {
  ArrayElementsWithAggregateUse(Logic a) {
    a = addInput('a', a, width: 4);
    final arr = LogicArray([4], 1, name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final results = <Logic>[];
    for (final leaf in arr.leafElements) {
      results.add(InverterMod(leaf).o);
    }
    addOutput('y', width: 4) <= results.rswizzle();

    // whole-array (aggregate) use, which blocks element inlining
    addOutputArray('arrCopy', dimensions: [4]) <= arr;
  }
}

/// An array provided as an input *port* whose leaves feed submodules.  Port
/// array elements are not clearable, so the port must remain; generation must
/// still be correct.
class ArrayPortElementsToSubmodules extends Module {
  ArrayPortElementsToSubmodules(LogicArray a) {
    a = addInputArray('a', a,
        dimensions: a.dimensions, elementWidth: a.elementWidth);
    final results = <Logic>[];
    for (final leaf in a.leafElements) {
      results.add(InverterMod(leaf, width: a.elementWidth).o);
    }
    addOutput('y', width: a.width) <= results.rswizzle();
  }
}

/// A struct with a [LogicArray] field, provided as a port, whose array leaves
/// feed submodules.  Struct-port array elements must NOT be inlined.
class StructWithArrayField extends LogicStructure {
  final LogicArray arr;
  final Logic flag;

  factory StructWithArrayField({String name = 'swaf'}) =>
      StructWithArrayField._(
        LogicArray([4], 1, name: 'arr'),
        Logic(name: 'flag'),
        name: name,
      );

  StructWithArrayField._(this.arr, this.flag, {super.name})
      : super([arr, flag]);

  @override
  StructWithArrayField clone({String? name}) =>
      StructWithArrayField(name: name ?? this.name);
}

/// Feeds the leaves of a struct-port array field into submodules.
class StructArrayFieldToSubmodules extends Module {
  StructArrayFieldToSubmodules(StructWithArrayField s) {
    s = StructWithArrayField()..gets(addInput('s', s, width: s.width));
    final results = <Logic>[];
    for (final leaf in s.arr.leafElements) {
      results.add(InverterMod(leaf).o);
    }
    addOutput('y', width: s.arr.width) <= results.rswizzle();
  }
}

class ArrayModuleWithNetIntermediates extends Module {
  ArrayModuleWithNetIntermediates(LogicArray a, LogicArray b) {
    a = addInOutArray('a', a,
        dimensions: a.dimensions,
        elementWidth: a.elementWidth,
        numUnpackedDimensions: a.numUnpackedDimensions);

    final intermediate = LogicArray.net(
      a.dimensions,
      a.elementWidth,
      name: 'intermediate',
      naming: Naming.reserved,
    );

    b = addInOutArray('b', b,
        dimensions: a.dimensions,
        elementWidth: a.elementWidth,
        numUnpackedDimensions: a.numUnpackedDimensions);

    intermediate <= a;
    b <= intermediate;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple 1d collapse', () async {
    final mod = SimpleLAPassthrough(LogicArray([4], 1));
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains('assign laOut = laIn;'));
  });

  test('array collapse for cross-module connection', () async {
    final mod = ArrayTopMod(Logic());
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains(RegExp(r'ArraySubModIn.*\.inp\(inp\)')));
    expect(sv, contains(RegExp(r'ArraySubModOut.*\.arrOut\(inp\)')));
  });

  test('array nets with intermediate collapse', () async {
    final mod = ArrayModuleWithNetIntermediates(
        LogicArray([3, 3], 1), LogicArray([3, 3], 1));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect (intermediate, a);'));
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect_0 (b, intermediate);'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('array assignment non-collapsing with shuffled assignment', () async {
    final mod = ArrayWithShuffledAssignment(LogicArray([4], 1));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, contains('assign b[0] = a[3];'));
    expect(sv, contains('assign b[3] = a[0];'));

    final vectors = [
      Vector({'a': LogicValue.of('01xz')}, {'b': LogicValue.of('zx10')}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('array nets with intermediate collapse with unpacked', () async {
    final mod = ArrayModuleWithNetIntermediates(
        LogicArray([3, 3], 1, numUnpackedDimensions: 2),
        LogicArray([3, 3], 1, numUnpackedDimensions: 2));
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect (intermediate, a);'));
    expect(sv,
        contains('net_connect #(.WIDTH(9)) net_connect_0 (b, intermediate);'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
  });

  test('collapse test 2d', () async {
    final mod = ArrayModule(LogicArray([4, 4], 1));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('assign d = c[0];'));
    expect(sv, contains('assign b = a;'));

    final vectors = [
      Vector({'a': 0}, {'b': 0}),
      Vector({'a': 123}, {'b': 123}),
      Vector({'c': 6}, {'d': 6}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('array element inlining', () {
    /// Expected `~a` result for the [ArrayElementFanout] configurations, where
    /// leaves are inverted and optionally consumed in [reversed] order.
    LogicValue expectedInverted(LogicValue a, int leafCount, int elementWidth,
        {required bool reversed}) {
      final leaves = [
        for (var i = 0; i < leafCount; i++)
          a.getRange(i * elementWidth, (i + 1) * elementWidth)
      ];
      return [
        for (var i = 0; i < leafCount; i++)
          ~leaves[reversed ? leafCount - 1 - i : i]
      ].rswizzle();
    }

    final fanoutConfigs = <({
      String name,
      List<int> dimensions,
      int elementWidth,
      bool reversed,
    })>[
      (name: '1d', dimensions: [4], elementWidth: 1, reversed: false),
      (name: '1d reversed', dimensions: [4], elementWidth: 1, reversed: true),
      (
        name: '1d wide elements', dimensions: [3], elementWidth: 4, //
        reversed: false
      ),
      (name: '2d', dimensions: [2, 2], elementWidth: 1, reversed: false),
      (name: '3d', dimensions: [2, 2, 2], elementWidth: 1, reversed: false),
      (
        name: '2d wide elements', dimensions: [2, 2], elementWidth: 3, //
        reversed: false
      ),
    ];

    for (final cfg in fanoutConfigs) {
      test('logic elements inline and drop the array (${cfg.name})', () async {
        final leafCount = cfg.dimensions.reduce((x, y) => x * y);
        final total = leafCount * cfg.elementWidth;

        final mod = ArrayElementFanout(Logic(width: total),
            dimensions: cfg.dimensions,
            elementWidth: cfg.elementWidth,
            reversed: cfg.reversed);
        await mod.build();
        final sv = mod.generateSynth();

        // the intermediate array (and every declaration of it) must be gone
        expect(sv, isNot(contains('arr')));

        final vectors = [
          for (final value in [0, 0xA, (1 << total) - 1])
            Vector({
              'a': value
            }, {
              'y': expectedInverted(
                  LogicValue.ofInt(value, total), leafCount, cfg.elementWidth,
                  reversed: cfg.reversed)
            })
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    final netConfigs =
        <({String name, List<int> dimensions, int elementWidth})>[
      (name: '1d', dimensions: [4], elementWidth: 1),
      (name: '2d', dimensions: [2, 2], elementWidth: 1),
      (name: '2d wide elements', dimensions: [2, 2], elementWidth: 2),
    ];

    for (final cfg in netConfigs) {
      test('net elements inline without net_connect (${cfg.name})', () async {
        final total = cfg.dimensions.reduce((x, y) => x * y) * cfg.elementWidth;

        final mod = NetArrayElementFanout(
            LogicNet(width: total), LogicNet(width: total),
            dimensions: cfg.dimensions, elementWidth: cfg.elementWidth);
        await mod.build();
        final sv = mod.generateSynth();

        // the intermediate array and its net_connects must be gone
        expect(sv, isNot(contains('arr')));
        expect(sv, isNot(contains('net_connect (arr')));

        final vectors = [
          for (final value in [0, 0xA, (1 << total) - 1])
            Vector({'a': value}, {'b': value})
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    for (final dimensions in [
      [4],
      [2, 2],
    ]) {
      test('partially-driven array is not inlined ($dimensions)', () async {
        final total = dimensions.reduce((x, y) => x * y);
        final mod = PartiallyDrivenArray(Logic(width: total - 2),
            dimensions: dimensions);
        await mod.build();
        final sv = mod.generateSynth();

        // the array must remain declared since undriven bits must stay `z`
        expect(sv, contains('arr'));

        final vectors = [
          Vector({'a': bin('01')}, {'y': LogicValue.ofString('z01z')}),
          Vector({'a': bin('10')}, {'y': LogicValue.ofString('z10z')}),
        ];
        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }

    test('aggregate-used array is not inlined', () async {
      final mod = ArrayElementsWithAggregateUse(Logic(width: 4));
      await mod.build();
      final sv = mod.generateSynth();

      // the array stays (aggregate use), so elements are not inlined into ports
      expect(sv, contains('arr'));
      expect(sv, isNot(contains('.i((a[')));

      final vectors = [
        Vector({'a': bin('0000')}, {'y': bin('1111'), 'arrCopy': bin('0000')}),
        Vector({'a': bin('1010')}, {'y': bin('0101'), 'arrCopy': bin('1010')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('input-array port elements are not inlined away', () async {
      final mod = ArrayPortElementsToSubmodules(LogicArray([2, 2], 2));
      await mod.build();
      final sv = mod.generateSynth();

      // the array port must remain declared
      expect(sv, contains('a'));

      final vectors = [
        Vector({'a': 0}, {'y': LogicValue.ofInt(~0, 8)}),
        Vector({'a': 0xA5}, {'y': LogicValue.ofInt(~0xA5, 8)}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('struct-port array field elements are not inlined', () async {
      final mod = StructArrayFieldToSubmodules(StructWithArrayField());
      await mod.build();

      final vectors = [
        // s = {flag, arr[4]}; arr is the low 4 bits, y = ~arr
        Vector({'s': 0x00}, {'y': 0xF}),
        Vector({'s': 0x14}, {'y': 0xB}),
        Vector({'s': 0x1F}, {'y': 0x0}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });
}
