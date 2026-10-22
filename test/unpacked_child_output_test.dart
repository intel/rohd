// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _ArrayChild extends Module {
  late final LogicArray result;

  _ArrayChild(Logic data) {
    data = addInput('data', data, width: 8);
    result = addOutputArray('result',
        dimensions: [2], elementWidth: 8, numUnpackedDimensions: 1);
    result.at([0]) <= data;
    result.at([1]) <= data + 1;
  }
}

class _ArrayParent extends Module {
  _ArrayParent({bool arrayOutput = false, bool procedural = false}) {
    final data = addInput('data', Logic(width: 8), width: 8);
    final received = LogicArray([2], 8,
        numUnpackedDimensions: 1, name: 'received', naming: Naming.reserved);
    if (procedural) {
      Combinational([
        received.at([0]) < data,
        received.at([1]) < data + 1,
      ]);
    } else {
      received <= _ArrayChild(data).result;
    }
    if (arrayOutput) {
      addOutputArray('result',
              dimensions: [2], elementWidth: 8, numUnpackedDimensions: 1)
          .gets(received);
    } else {
      addOutput('result', width: 16) <= received;
    }
  }
}

class _ArrayRelay extends Module {
  _ArrayRelay() {
    final data = addInput('data', Logic(width: 8), width: 8);
    addOutputArray('result',
            dimensions: [2], elementWidth: 8, numUnpackedDimensions: 1)
        .gets(_ArrayChild(data).result);
  }
}

void main() {
  tearDown(Simulator.reset);

  test('child-driven unpacked output ports default to nets', () async {
    final dut = _ArrayRelay();
    await dut.build();
    expect(dut.dumpSystemVerilog(),
        contains('output wire logic [7:0] result [1:0]'));
    final vectors = [
      Vector({'data': 1}, {'result': 0x0201}),
      Vector({'data': 9}, {'result': 0x0a09}),
    ];
    await SimCompare.checkFunctionalVector(dut, vectors);
    SimCompare.checkIverilogVector(dut, vectors);
  });

  test('child-driven output ports honor explicit object-type configuration',
      () async {
    final dut = _ArrayRelay();
    await dut.build();
    expect(
        dut.dumpSystemVerilog(
            configuration: const SystemVerilogSynthesizerConfiguration(
                outputPortType: SystemVerilogPortTypeConfiguration())),
        contains('output var logic [7:0] result [1:0]'));
    expect(
        dut.dumpSystemVerilog(
            configuration: const SystemVerilogSynthesizerConfiguration(
                outputPortType: SystemVerilogPortTypeConfiguration(
                    objectType: SystemVerilogPortType.implicit,
                    dataType: SystemVerilogPortType.implicit))),
        contains('output [7:0] result [1:0]'));
  });

  for (final arrayOutput in [false, true]) {
    for (final procedural in [false, true]) {
      // Child-connected arrays must use nets, but arrays assigned by an
      // always block must retain variable declarations.
      test('unpacked array output=$arrayOutput procedural=$procedural',
          () async {
        final dut =
            _ArrayParent(arrayOutput: arrayOutput, procedural: procedural);
        await dut.build();
        final sv = dut.dumpSystemVerilog();
        expect(
            sv,
            contains('${procedural ? 'logic' : 'wire'} '
                '[7:0] received [1:0];'));
        final vectors = [
          Vector({'data': 1}, {'result': 0x0201}),
          Vector({'data': 9}, {'result': 0x0a09}),
          Vector({'data': 0xfe}, {'result': 0xfffe}),
        ];
        await SimCompare.checkFunctionalVector(dut, vectors);
        SimCompare.checkIverilogVector(dut, vectors);
      });
    }
  }
}
