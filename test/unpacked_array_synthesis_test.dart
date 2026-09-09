// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unpacked_array_synthesis_test.dart
// Tests for unpacked-array synthesis and input connection inlining.
//
// 2026 September 9
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum ArrayDrive { constant, elements, live }

class UnpackedConsumer extends Module {
  UnpackedConsumer(LogicArray source) {
    final array = addInputArray('array', source,
        dimensions: source.dimensions,
        elementWidth: source.elementWidth,
        numUnpackedDimensions: source.numUnpackedDimensions);
    addOutput('observed', width: array.width) <=
        array.leafElements.toList().rswizzle();
  }
}

class UnpackedInputTop extends Module {
  UnpackedInputTop({
    required List<int> dimensions,
    required int elementWidth,
    required int numUnpackedDimensions,
    required ArrayDrive drive,
    dynamic value = 0,
    Naming naming = Naming.mergeable,
  }) {
    final array = LogicArray(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        naming: naming,
        name: 'tieoff');
    final child = UnpackedConsumer(array);
    final constant = LogicValue.of(value, width: array.width);
    switch (drive) {
      case ArrayDrive.constant:
        array <= Const(constant);
      case ArrayDrive.elements:
        var offset = 0;
        for (final leaf in array.leafElements) {
          leaf <= Const(constant.getRange(offset, offset + leaf.width));
          offset += leaf.width;
        }
      case ArrayDrive.live:
        array <=
            addInput('value', Logic(width: array.width), width: array.width);
    }
    addOutput('observed', width: array.width) <= child.output('observed');
  }
}

void main() {
  tearDown(Simulator.reset);

  final shapes = [
    (name: 'packed singleton', dimensions: [1], width: 2, unpacked: 0),
    (name: 'singleton bit', dimensions: [1], width: 1, unpacked: 1),
    (name: 'singleton vector', dimensions: [1], width: 2, unpacked: 1),
    (name: 'bit array', dimensions: [4], width: 1, unpacked: 1),
    (name: 'vector array', dimensions: [3], width: 2, unpacked: 1),
    (name: 'mixed dimensions', dimensions: [1, 3], width: 2, unpacked: 1),
    (name: 'nested singleton', dimensions: [1, 1], width: 2, unpacked: 2),
    (name: 'nested array', dimensions: [2, 2], width: 2, unpacked: 2),
  ];

  for (final shape in shapes) {
    for (final drive in ArrayDrive.values) {
      final name = '${shape.name}, ${drive.name}';
      final width = shape.dimensions
          .fold(shape.width, (product, dimension) => product * dimension);
      final values = [
        LogicValue.of(0, width: width),
        LogicValue.of(BigInt.parse('b6d3', radix: 16).toUnsigned(width),
            width: width),
        LogicValue.filled(width, LogicValue.x),
        LogicValue.filled(width, LogicValue.z),
      ];

      UnpackedInputTop makeModule(LogicValue value) => UnpackedInputTop(
          dimensions: shape.dimensions,
          elementWidth: shape.width,
          numUnpackedDimensions: shape.unpacked,
          drive: drive,
          value: value);

      test('$name preserves ROHD values', () async {
        if (drive == ArrayDrive.live) {
          final module = makeModule(values.first);
          await module.build();
          await SimCompare.checkFunctionalVector(module, [
            for (final value in values)
              Vector({'value': value}, {'observed': value}),
          ]);
        } else {
          for (final value in values) {
            final module = makeModule(value);
            await module.build();
            expect(module.output('observed').value, value);
          }
        }
      });

      test('$name compiles with Verilator', () async {
        for (final value in values.take(2)) {
          final module = makeModule(value);
          await module.build();
          if (!SimCompare.checkVerilatorCompilation(module)) {
            return;
          }
        }
      }, tags: ['verilator']);
    }
  }

  test('unpacked concatenation preserves element order', () async {
    final module = UnpackedInputTop(
        dimensions: [3],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.elements,
        value: 0x39);
    await module.build();
    expect(module.generateSynth(), contains(".array(({2'h3, 2'h2, 2'h1}))"));
  });

  for (final value in [0, 2, LogicValue.x]) {
    test('singleton literal $value keeps unpacked braces', () async {
      final module = UnpackedInputTop(
          dimensions: [1],
          elementWidth: 2,
          numUnpackedDimensions: 1,
          drive: ArrayDrive.constant,
          value: value);
      await module.build();
      final literal = LogicValue.of(value, width: 2);
      expect(module.generateSynth(), contains('.array(({$literal}))'));
    });
  }

  test('live singleton keeps unpacked braces', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.live);
    await module.build();
    expect(module.generateSynth(), contains('.array(({value}))'));
  });

  test('floating singleton retains its unpacked array shape', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.constant,
        value: LogicValue.z);
    await module.build();
    final verilog = module.generateSynth();
    expect(verilog, contains('logic [1:0] array [0:0];'));
    expect(verilog, contains('.array(array)'));
  });

  test('packed singleton keeps its scalar connection', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 0,
        drive: ArrayDrive.constant,
        value: 2);
    await module.build();
    expect(module.generateSynth(), contains(".array((2'h2))"));
  });

  test('preserved singleton array stays declared', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.constant,
        naming: Naming.reserved);
    await module.build();
    final verilog = module.generateSynth();
    expect(verilog, contains('logic [1:0] tieoff [0:0];'));
    expect(verilog, contains('.array(tieoff)'));
  });
}
