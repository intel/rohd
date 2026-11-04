// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// packed_array_logic_merge_test.dart
// Tests SystemVerilog merging between packed arrays and scalar logic.
//
// 2026 November 2
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _PackedArrayScalarMerge extends Module {
  _PackedArrayScalarMerge() {
    final data = addInput('data', Logic(width: 8), width: 8);
    final intermediate = LogicArray(
      [2, 2],
      2,
      name: 'intermediate',
      naming: Naming.mergeable,
    );
    intermediate <= data;

    final scalar = Logic(width: 8, name: 'scalar', naming: Naming.mergeable);
    scalar <= intermediate;
    addOutput('out', width: 8) <= scalar;
  }
}

class _PartialPackedArrayScalarMerge extends Module {
  _PartialPackedArrayScalarMerge() {
    final data = addInput('data', Logic(width: 8), width: 8);
    final intermediate = LogicArray(
      [2],
      2,
      name: 'partialIntermediate',
      naming: Naming.mergeable,
    );
    intermediate <= data.getRange(0, 4);

    final scalar =
        Logic(width: 4, name: 'partialScalar', naming: Naming.mergeable);
    scalar <= intermediate;
    addOutput('out', width: 4) <= scalar;
  }
}

class _UnpackedArrayScalarMerge extends Module {
  _UnpackedArrayScalarMerge() {
    final data = addInput('data', Logic(width: 4), width: 4);
    final intermediate = LogicArray(
      [2],
      2,
      name: 'unpackedIntermediate',
      naming: Naming.mergeable,
      numUnpackedDimensions: 1,
    );
    intermediate <= data;

    final scalar =
        Logic(width: 4, name: 'unpackedScalar', naming: Naming.mergeable);
    scalar <= intermediate;
    addOutput('out', width: 4) <= scalar;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('fully assigned packed arrays merge into a scalar output', () async {
    final module = _PackedArrayScalarMerge();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, contains('assign out = data;'), reason: sv);
    expect(sv, isNot(contains('intermediate')), reason: sv);
    expect(sv, isNot(contains('// concat')), reason: sv);

    final vectors = [
      Vector({'data': 0x00}, {'out': 0x00}),
      Vector({'data': 0xa5}, {'out': 0xa5}),
      Vector({'data': 0xff}, {'out': 0xff}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('partial packed-array sources remain explicit', () async {
    final module = _PartialPackedArrayScalarMerge();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, isNot(contains('assign out = data;')), reason: sv);
    expect(sv, contains('// concat'), reason: sv);

    final vectors = [
      Vector({'data': 0x00}, {'out': 0x0}),
      Vector({'data': 0xa5}, {'out': 0x5}),
      Vector({'data': 0xff}, {'out': 0xf}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('unpacked array sources remain explicit', () async {
    final module = _UnpackedArrayScalarMerge();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, isNot(contains('assign out = data;')), reason: sv);
    expect(sv, contains('// concat'), reason: sv);

    final vectors = [
      Vector({'data': 0x0}, {'out': 0x0}),
      Vector({'data': 0x9}, {'out': 0x9}),
      Vector({'data': 0xf}, {'out': 0xf}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
  });
}
