// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// nested_array_struct_port_synthesis_test.dart
// Tests synthesis of nested LogicArray fields in typed LogicStructure ports.
//
// 2026 August 18
// Author: Max Korbel <max.korbel@intel.com>

@TestOn('vm')
library;

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ArrayRecord extends LogicStructure {
  final Logic header;
  final LogicArray entries;
  final Logic trailer;

  factory ArrayRecord({
    String name = 'arrayRecord',
    List<int> dimensions = const [3],
    int numUnpackedDimensions = 0,
  }) =>
      ArrayRecord._(
        Logic(name: 'header', width: 2),
        LogicArray(
          dimensions,
          4,
          name: 'entries',
          numUnpackedDimensions: numUnpackedDimensions,
        ),
        Logic(name: 'trailer', width: 3),
        name: name,
      );

  ArrayRecord._(
    this.header,
    this.entries,
    this.trailer, {
    required String name,
  }) : super([header, entries, trailer], name: name);

  @override
  ArrayRecord clone({String? name}) => ArrayRecord(
        name: name ?? this.name,
        dimensions: entries.dimensions,
        numUnpackedDimensions: entries.numUnpackedDimensions,
      );
}

class ArrayRecordProducer extends Module {
  late final ArrayRecord outputData;

  ArrayRecordProducer({
    required List<int> dimensions,
    required int numUnpackedDimensions,
  }) {
    outputData = addTypedOutput(
      'outputData',
      ({name = 'outputData'}) => ArrayRecord(
        name: name,
        dimensions: dimensions,
        numUnpackedDimensions: numUnpackedDimensions,
      ),
    );

    outputData.header <= Const(0, width: outputData.header.width);
    for (final entry in outputData.entries.leafElements) {
      entry <= Const(0, width: entry.width);
    }
    outputData.trailer <= Const(0, width: outputData.trailer.width);
  }
}

class ArrayRecordConsumer extends Module {
  late final Logic observed;

  ArrayRecordConsumer(ArrayRecord source, {required bool consumeInput}) {
    final inputData = addTypedInput('inputData', source);

    observed = addOutput('observed')
      ..gets(
        consumeInput ? inputData.entries.leafElements.first[0] : Const(0),
      );
  }
}

class ArrayRecordHierarchy extends Module {
  ArrayRecordHierarchy({
    List<int> dimensions = const [3],
    int numUnpackedDimensions = 0,
    bool consumeInput = false,
    bool connectProducerDirectly = false,
  }) {
    final producer = ArrayRecordProducer(
      dimensions: dimensions,
      numUnpackedDimensions: numUnpackedDimensions,
    );
    final source = connectProducerDirectly
        ? producer.outputData
        : ArrayRecord(
            name: 'intermediate',
            dimensions: dimensions,
            numUnpackedDimensions: numUnpackedDimensions,
          );
    final consumer = ArrayRecordConsumer(
      source,
      consumeInput: consumeInput,
    );

    if (!connectProducerDirectly) {
      source.gets(producer.outputData);
    }
    addOutput('observed').gets(consumer.observed);
  }
}

class RootArrayPassThrough extends Module {
  late final LogicArray outputData;

  RootArrayPassThrough(LogicArray source) {
    final inputData = addTypedInput('inputData', source);
    outputData = addTypedOutput('outputData', inputData.clone)..gets(inputData);
  }
}

void main() {
  tearDown(Simulator.reset);

  group('nested array structure input synthesis', () {
    final testCases = [
      (
        name: 'unused one-dimensional packed array',
        dimensions: const [3],
        numUnpackedDimensions: 0,
        consumeInput: false,
        connectProducerDirectly: false,
        expectedDeclaration: 'logic [2:0][3:0] inputData_entries;',
      ),
      (
        name: 'unused multi-dimensional packed array',
        dimensions: const [2, 3],
        numUnpackedDimensions: 0,
        consumeInput: false,
        connectProducerDirectly: false,
        expectedDeclaration: 'logic [1:0][2:0][3:0] inputData_entries;',
      ),
      (
        name: 'unused array with an unpacked dimension',
        dimensions: const [2, 3],
        numUnpackedDimensions: 1,
        consumeInput: false,
        connectProducerDirectly: false,
        expectedDeclaration: 'logic [2:0][3:0] inputData_entries [1:0];',
      ),
      (
        name: 'internally consumed nested array input',
        dimensions: const [3],
        numUnpackedDimensions: 0,
        consumeInput: true,
        connectProducerDirectly: false,
        expectedDeclaration: null,
      ),
      (
        name: 'producer output connected directly',
        dimensions: const [3],
        numUnpackedDimensions: 0,
        consumeInput: false,
        connectProducerDirectly: true,
        expectedDeclaration: null,
      ),
    ];

    for (final testCase in testCases) {
      test(testCase.name, () async {
        final module = ArrayRecordHierarchy(
          dimensions: testCase.dimensions,
          numUnpackedDimensions: testCase.numUnpackedDimensions,
          consumeInput: testCase.consumeInput,
          connectProducerDirectly: testCase.connectProducerDirectly,
        );
        await module.build();

        final generated = module.dumpSystemVerilog().output;

        expect(generated, contains('module ArrayRecordHierarchy'));
        expect(generated, contains('.inputData('));
        if (testCase.expectedDeclaration case final expectedDeclaration?) {
          expect(generated, contains(expectedDeclaration));
        }
        SimCompare.checkIverilogVector(module, [], buildOnly: true);
      });
    }
  });

  test('root typed LogicArray ports retain their declaration shape', () async {
    final module = RootArrayPassThrough(LogicArray([2, 3], 4));
    await module.build();

    final generated = module.dumpSystemVerilog().output;

    expect(generated, contains('input logic [1:0][2:0][3:0] inputData'));
    expect(generated, contains('output logic [1:0][2:0][3:0] outputData'));
    expect(generated, contains('assign outputData = inputData;'));
    SimCompare.checkIverilogVector(module, [], buildOnly: true);
  });
}
