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

/// Inverts a single bit.
class OneBitInverter extends Module {
  Logic get o => output('o');
  OneBitInverter(Logic i) {
    i = addInput('i', i);
    addOutput('o') <= ~i;
  }
}

/// Bidirectionally connects two single-bit nets.
class OneBitNetPassthrough extends Module {
  OneBitNetPassthrough(Logic x, Logic y) {
    x = addInOut('x', x);
    y = addInOut('y', y);
    x <= y;
  }
}

/// A flat input bus blasted into an array, each element feeding a 1-bit
/// submodule input.  The intermediate array should disappear and the submodule
/// ports should reference `a[i]` directly.
class LogicArrayElementsToSubmodules extends Module {
  LogicArrayElementsToSubmodules(Logic a, {bool reversed = false}) {
    a = addInput('a', a, width: 4);
    final arr = LogicArray([4], 1, name: 'arr', naming: Naming.mergeable);
    arr <= a;

    final results = <Logic>[];
    for (var i = 0; i < 4; i++) {
      final srcIdx = reversed ? 3 - i : i;
      results.add(OneBitInverter(arr.elements[srcIdx]).o);
    }

    addOutput('y', width: 4) <= results.rswizzle();
  }
}

/// A flat inout bus blasted into a net array, each element feeding a 1-bit
/// submodule inout, which bidirectionally connects to an output bus.
class NetArrayElementsToSubmodules extends Module {
  NetArrayElementsToSubmodules(LogicNet a, LogicNet b) {
    a = addInOut('a', a, width: 4);
    b = addInOut('b', b, width: 4);
    final arr = LogicArray.net([4], 1, name: 'arr', naming: Naming.mergeable);
    arr <= a;

    for (var i = 0; i < 4; i++) {
      OneBitNetPassthrough(arr.elements[i], b.elements[i]);
    }
  }
}

/// An array where only some elements are driven (by submodule-feeding subsets)
/// and the rest are undriven, with the whole array reconstructed via a swizzle.
/// This must NOT be inlined away (partial inlining would change `x`/`z`
/// behavior of the undriven bits).
class PartiallyDrivenArray extends Module {
  PartiallyDrivenArray(Logic a) {
    a = addInput('a', a, width: 2);
    final arr = LogicArray([4], 1, name: 'arr', naming: Naming.mergeable);

    // only drive the middle two bits from `a`
    arr.elements[1] <= a[0];
    arr.elements[2] <= a[1];

    addOutput('y', width: 4) <= arr.elements.rswizzle();
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
    test('logic elements inline directly into submodules', () async {
      final mod = LogicArrayElementsToSubmodules(Logic(width: 4));
      await mod.build();

      final sv = mod.generateSynth();

      // the intermediate array should be gone
      expect(sv, isNot(contains('arr')));
      // submodule inputs should reference `a[i]` directly
      for (var i = 0; i < 4; i++) {
        expect(sv, contains('.i((a[$i]))'));
      }

      final vectors = [
        Vector({'a': bin('0000')}, {'y': bin('1111')}),
        Vector({'a': bin('1010')}, {'y': bin('0101')}),
        Vector({'a': bin('1100')}, {'y': bin('0011')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('reversed/out-of-order logic elements inline directly', () async {
      final mod =
          LogicArrayElementsToSubmodules(Logic(width: 4), reversed: true);
      await mod.build();

      final sv = mod.generateSynth();

      expect(sv, isNot(contains('arr')));
      for (var i = 0; i < 4; i++) {
        expect(sv, contains('.i((a[$i]))'));
      }

      // y[i] = ~a[3-i]
      final vectors = [
        Vector({'a': bin('0000')}, {'y': bin('1111')}),
        Vector({'a': bin('1010')}, {'y': bin('1010')}),
        Vector({'a': bin('1000')}, {'y': bin('1110')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('net elements inline directly without net_connect', () async {
      final mod =
          NetArrayElementsToSubmodules(LogicNet(width: 4), LogicNet(width: 4));
      await mod.build();

      final sv = mod.generateSynth();

      // the intermediate array and its net_connects should be gone
      expect(sv, isNot(contains('wire [3:0] arr')));
      expect(sv, isNot(contains('net_connect (arr')));
      for (var i = 0; i < 4; i++) {
        expect(sv, contains('.x((a[$i]))'));
      }

      final vectors = [
        Vector({'a': bin('0000')}, {'b': bin('0000')}),
        Vector({'a': bin('1010')}, {'b': bin('1010')}),
        Vector({'a': bin('1101')}, {'b': bin('1101')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('partially-driven array is not inlined', () async {
      final mod = PartiallyDrivenArray(Logic(width: 2));
      await mod.build();

      final sv = mod.generateSynth();

      // the array must remain declared since undriven bits must stay `z`
      expect(sv, contains('logic [3:0] arr'));

      final vectors = [
        Vector({'a': bin('01')}, {'y': LogicValue.ofString('z01z')}),
        Vector({'a': bin('10')}, {'y': LogicValue.ofString('z10z')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });
}
