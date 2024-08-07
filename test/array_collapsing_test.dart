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

class ArrayModule extends Module {
  ArrayModule(LogicArray a) {
    final inpA = addInputArray('a', a, dimensions: a.dimensions);
    addOutputArray('b', dimensions: a.dimensions) <= inpA;

    final inoutA = addInOutArray('c', a, dimensions: a.dimensions);
    addOutputArray('d', dimensions: [a.dimensions.last]) <=
        inoutA.elements.first;
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
}
