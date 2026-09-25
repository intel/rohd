// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// submodule_output_slice_repro_test.dart
// Reproduction tests for submodule output connections to bus and array slices
//
// 2026 September 25
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum DestinationKind { bus, packedArray, unpackedArray, wholeBus }

class SyntheticStage extends Module {
  SyntheticStage(Logic data) : super(name: 'stage') {
    data = addInput('data', data, width: data.width);
    addOutput('result', width: data.width) <= ~data;
  }
}

class SyntheticTop extends Module {
  SyntheticTop(DestinationKind kind) : super(name: 'synthetic_top') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final Logic observed;
    if (kind == DestinationKind.packedArray ||
        kind == DestinationKind.unpackedArray) {
      observed = addOutputArray('observed',
          dimensions: [4],
          numUnpackedDimensions: kind == DestinationKind.unpackedArray ? 1 : 0);
    } else {
      observed = addOutput('observed', width: 4);
    }

    if (kind == DestinationKind.wholeBus) {
      observed <= SyntheticStage(data).output('result');
      return;
    }

    final results = [
      for (var index = 0; index < 4; index++)
        SyntheticStage(data[index]).output('result'),
    ];
    if (observed is LogicArray) {
      for (var index = 0; index < 4; index++) {
        observed.elements[index] <= results[index];
      }
    } else {
      observed.assignSubset(results);
    }
  }
}

void main() {
  tearDown(Simulator.reset);

  for (final kind in DestinationKind.values) {
    test('child output maps directly to ${kind.name}', () async {
      final module = SyntheticTop(kind);
      await module.build();

      for (var value = 0; value < 16; value++) {
        module.input('data').put(value);
        expect(module.output('observed').value.toInt(), value ^ 15);
      }

      final verilog = module.generateSynth();
      if (kind == DestinationKind.wholeBus) {
        expect(verilog, matches(r'\.result\(\s*observed\s*\)'),
            reason: verilog);
      } else {
        for (var index = 0; index < 4; index++) {
          expect(
              verilog, matches('\\.result\\(\\s*observed\\[$index\\]\\s*\\)'),
              reason: verilog);
        }
      }
      final vectors = [
        for (var value = 0; value < 16; value++)
          Vector({'data': value}, {'observed': value ^ 15}),
        Vector({'data': LogicValue.ofString('10xz')},
            {'observed': LogicValue.ofString('01xx')}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      if (kind == DestinationKind.unpackedArray) {
        SimCompare.checkVerilatorVector(module, vectors.take(16).toList());
      } else {
        SimCompare.checkIverilogVector(module, vectors);
      }
    });
  }
}
