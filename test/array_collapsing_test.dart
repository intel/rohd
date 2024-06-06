// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// array_collapsing_test.dart
// Tests for array collapsing
//
// 2024 June 5
// Author: Shankar Sharma <shankar.sharma@intel.com>

import 'dart:io';

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

    //TODO: what if unpacked?
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
    SimCompare.checkIverilogVector(mod, vectors);
    //TODO: what if unpacked?
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
