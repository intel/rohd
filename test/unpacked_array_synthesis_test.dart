// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unpacked_array_synthesis_test.dart
// Tests for unpacked-array synthesis and input connection inlining.
//
// 2026 September 15
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

class ParentArrayPortToChild extends Module {
  ParentArrayPortToChild(LogicArray source) {
    source = addInputArray(
      'source',
      source,
      dimensions: source.dimensions,
      elementWidth: source.elementWidth,
      numUnpackedDimensions: source.numUnpackedDimensions,
    );
    final child = UnpackedConsumer(source);
    addOutput('observed', width: source.width) <= child.output('observed');
  }
}

class _ArrayElementConsumer extends Module {
  Logic get y => output('y');

  _ArrayElementConsumer(Logic a, {required super.name})
      : super(definitionName: 'ArrayElementConsumer_W${a.width}') {
    a = addInput('a', a, width: a.width);
    addOutput('y') <= a.or();
  }
}

class _ArrayElementProducer extends Module {
  Logic get y => output('y');

  _ArrayElementProducer(Logic a, {required super.name})
      : super(definitionName: 'ArrayElementProducer_W${a.width}') {
    a = addInput('a', a, width: a.width);
    addOutput('y', width: a.width) <= a;
  }
}

class _ParentArrayElementsToChildren extends Module {
  _ParentArrayElementsToChildren(LogicArray values)
      : super(definitionName: 'ParentArrayElementsToChildren') {
    values = addInputArray(
      'values',
      values,
      dimensions: values.dimensions,
      elementWidth: values.elementWidth,
    );
    final low = _ArrayElementConsumer(values.elements[0], name: 'low');
    final high = _ArrayElementConsumer(values.elements[1], name: 'high');
    addOutput('observed', width: 2) <= [high.y, low.y].swizzle();
  }
}

class _ParentChildrenToArrayElements extends Module {
  _ParentChildrenToArrayElements(Logic lowValue, Logic highValue)
      : super(definitionName: 'ParentChildrenToArrayElements') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    final low = _ArrayElementProducer(lowValue, name: 'low');
    final high = _ArrayElementProducer(highValue, name: 'high');
    values.elements[0] <= low.y;
    values.elements[1] <= high.y;
  }
}

class _ArrayPackConsumer extends Module {
  Logic get observed => output('observed');

  _ArrayPackConsumer(LogicArray values, {required super.name})
      : super(definitionName: 'ArrayPackConsumer_W${values.width}') {
    values = addInputArray(
      'values',
      values,
      dimensions: values.dimensions,
      elementWidth: values.elementWidth,
    );
    addOutput('observed', width: values.width) <= values;
  }
}

class _ParentElementsToAggregateChild extends Module {
  _ParentElementsToAggregateChild(Logic lowValue, Logic highValue)
      : super(definitionName: 'ParentElementsToAggregateChild') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = LogicArray([2], 8, name: 'values');
    values.elements[0] <= lowValue;
    values.elements[1] <= highValue;
    final child = _ArrayPackConsumer(values, name: 'consumer');
    addOutput('observed', width: values.width) <= child.observed;
  }
}

class _ArrayPackProducer extends Module {
  LogicArray get values => output('values') as LogicArray;

  _ArrayPackProducer(Logic lowValue, Logic highValue, {required super.name})
      : super(definitionName: 'ArrayPackProducer_W${lowValue.width * 2}') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    values.elements[0] <= lowValue;
    values.elements[1] <= highValue;
  }
}

class _AggregateChildToParentOutput extends Module {
  _AggregateChildToParentOutput(Logic lowValue, Logic highValue)
      : super(definitionName: 'AggregateChildToParentOutput') {
    lowValue = addInput('lowValue', lowValue, width: lowValue.width);
    highValue = addInput('highValue', highValue, width: highValue.width);
    final child = _ArrayPackProducer(lowValue, highValue, name: 'source');
    final values = addOutputArray('values', dimensions: [2], elementWidth: 8);
    values <= child.values;
  }
}

class ReorderedParentArrayPortToChild extends Module {
  ReorderedParentArrayPortToChild(LogicArray source) {
    source = addInputArray(
      'source',
      source,
      dimensions: source.dimensions,
      elementWidth: source.elementWidth,
      numUnpackedDimensions: source.numUnpackedDimensions,
    );
    final reordered = LogicArray(
      source.dimensions,
      source.elementWidth,
      name: 'reordered',
      numUnpackedDimensions: source.numUnpackedDimensions,
      naming: Naming.mergeable,
    );
    for (final (index, element) in reordered.elements.indexed) {
      element <= source.elements[reordered.elements.length - index - 1];
    }
    final child = UnpackedConsumer(reordered);
    addOutput('observed', width: source.width) <= child.output('observed');
  }
}

class ArrayDriveSimulationTop extends Module {
  final expected = <String, LogicValue>{};

  ArrayDriveSimulationTop(List<int> dimensions, int unpacked) {
    final width =
        dimensions.fold(2, (product, dimension) => product * dimension);
    final inputValue = addInput('value', Logic(width: width), width: width);
    for (final drive in ArrayDrive.values) {
      final values = drive == ArrayDrive.live ? [0] : [0, 0x39];
      for (final value in values) {
        final child = UnpackedInputTop(
            dimensions: dimensions,
            elementWidth: 2,
            numUnpackedDimensions: unpacked,
            drive: drive,
            value: value);
        final outputName = '${drive.name}_$value';
        addOutput(outputName, width: width) <= child.output('observed');
        if (drive == ArrayDrive.live) {
          child.inputSource('value') <= inputValue;
        } else {
          expected[outputName] = LogicValue.of(value, width: width);
        }
      }
    }
  }
}

void main() {
  tearDown(Simulator.reset);

  for (final shape in [
    (dimensions: [1], unpacked: 1),
    (dimensions: [3], unpacked: 1),
    (dimensions: [1, 3], unpacked: 1),
    (dimensions: [2, 2], unpacked: 2),
  ]) {
    test('Verilator simulates all drivers for $shape', () async {
      final module = ArrayDriveSimulationTop(shape.dimensions, shape.unpacked);
      await module.build();
      SimCompare.checkVerilatorVector(module, [
        for (final value in [0, 0x39, 0xa6, 0xff])
          Vector({'value': value}, {...module.expected, 'live_0': value}),
      ]);
    }, tags: ['verilator']);
  }

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
        final module = makeModule(values[1]);
        await module.build();
        SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
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
    expect(
        module.dumpSystemVerilog(), contains(".array(({2'h3, 2'h2, 2'h1}))"));
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
      expect(module.dumpSystemVerilog(), contains('.array(({$literal}))'));
    });
  }

  test('live singleton keeps unpacked braces', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.live);
    await module.build();
    expect(module.dumpSystemVerilog(), contains('.array(({value}))'));
  });

  test('full-width parent array port connects directly to child', () async {
    final module = ParentArrayPortToChild(
      LogicArray([3], 2, numUnpackedDimensions: 1),
    );
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('input logic [1:0] source [2:0]'));
    expect(verilog, contains('.array(source)'));
    expect(verilog, isNot(contains('logic [1:0] array [2:0];')));

    SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
  }, tags: ['verilator']);

  test('packed parent array elements connect directly to scalar child inputs',
      () async {
    final module = _ParentArrayElementsToChildren(
      LogicArray([2], 8, name: 'values'),
    );
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('.a(values[0])'));
    expect(verilog, contains('.a(values[1])'));

    await SimCompare.checkFunctionalVector(module, [
      Vector({'values': 0x0000}, {'observed': 0}),
      Vector({'values': 0x8001}, {'observed': 3}),
      Vector({'values': 0x0100}, {'observed': 2}),
    ]);
    SimCompare.checkIverilogVector(module, [
      Vector({'values': 0x0000}, {'observed': 0}),
      Vector({'values': 0x8001}, {'observed': 3}),
      Vector({'values': 0x0100}, {'observed': 2}),
    ]);
  });

  test('scalar child outputs pack directly into a parent array output',
      () async {
    final module =
        _ParentChildrenToArrayElements(Logic(width: 8), Logic(width: 8));
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('.y(values[0])'));
    expect(verilog, contains('.y(values[1])'));

    final vectors = [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'values': 0xa55a},
      ),
      Vector(
        {'lowValue': 0x01, 'highValue': 0x80},
        {'values': 0x8001},
      ),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('parent elements pack into aggregate child inputs', () async {
    final module =
        _ParentElementsToAggregateChild(Logic(width: 8), Logic(width: 8));
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('.values(values)'));

    final vectors = [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'observed': 0xa55a},
      ),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('aggregate child outputs stay packed at parent output ports', () async {
    final module =
        _AggregateChildToParentOutput(Logic(width: 8), Logic(width: 8));
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('.values(values)'));

    final vectors = [
      Vector(
        {'lowValue': 0x5a, 'highValue': 0xa5},
        {'values': 0xa55a},
      ),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('reordered parent array preserves element order at child', () async {
    final module = ReorderedParentArrayPortToChild(
      LogicArray([3], 2, numUnpackedDimensions: 1),
    );
    await module.build();

    final verilog = module.dumpSystemVerilog();
    expect(verilog, isNot(contains('.array(source)')));
    expect(verilog, isNot(contains('reordered')));

    await SimCompare.checkFunctionalVector(
      module,
      [
        Vector({'source': 0x39}, {'observed': 0x1b})
      ],
    );
    SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
  }, tags: ['verilator']);

  test('floating singleton retains its unpacked array shape', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.constant,
        value: LogicValue.z);
    await module.build();
    final verilog = module.dumpSystemVerilog();
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
    expect(module.dumpSystemVerilog(), contains(".array((2'h2))"));
  });

  test('preserved singleton array stays declared', () async {
    final module = UnpackedInputTop(
        dimensions: [1],
        elementWidth: 2,
        numUnpackedDimensions: 1,
        drive: ArrayDrive.constant,
        naming: Naming.reserved);
    await module.build();
    final verilog = module.dumpSystemVerilog();
    expect(verilog, contains('logic [1:0] tieoff [0:0];'));
    expect(verilog, contains('.array(tieoff)'));
  });
}
