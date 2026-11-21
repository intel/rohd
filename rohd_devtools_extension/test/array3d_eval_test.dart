// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Test: 3D LogicArray transitive evaluation via the netlist evaluator.
//
// Verifies that `evaluateSignalOnDemand` correctly resolves inner-dimension
// array element signals that do NOT have explicit $slice cells (only the
// outermost dimension gets $slice cells from `_subsetReceiveArrayPort`).
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';

/// Leaf module (forces synthesis of inner module).
class _Leaf extends Module {
  _Leaf(Logic inp) : super(name: 'Leaf') {
    final i = addInput('i', inp, width: 8);
    addOutput('o', width: 8) <= i;
  }
}

/// Module with a 3D array input [2,3,4] x 8 bits.
/// Uses one element through a sub-module to force netlist synthesis.
class _Inner3D extends Module {
  _Inner3D(Logic src) : super(name: 'Inner3D') {
    final inp = addInputArray(
      'data',
      src,
      dimensions: [2, 3, 4],
      elementWidth: 8,
    );
    final leaf = _Leaf(inp.elements[0].elements[0].elements[0]);
    addOutput('out', width: 8) <= leaf.output('o');
  }
}

/// Top wrapper.
class _Top3D extends Module {
  _Top3D() : super(name: 'Top3D') {
    final src = LogicArray([2, 3, 4], 8, name: 'dataSrc');
    final inp = addInputArray(
      'data',
      src,
      dimensions: [2, 3, 4],
      elementWidth: 8,
    );
    final inner = _Inner3D(inp);
    addOutput('out', width: 8) <= inner.output('out');
  }
}

void main() {
  late _Top3D top;
  late NetlistService ns;
  late Map<String, dynamic> modules;
  late NetlistEvaluator evaluator;

  setUpAll(() async {
    top = _Top3D();
    await top.build();
    ns = NetlistService(top);
    final full = jsonDecode(ns.json) as Map<String, dynamic>;
    modules = full['modules'] as Map<String, dynamic>;
    evaluator = NetlistEvaluator(modules);
  });

  /// Helper: extract just the hex digits from evaluator output.
  /// Handles both "0xHEX" and "width'hHEX" formats.
  /// Pads to the expected nibble count based on width for comparison.
  String hexOf(String value, int width) {
    String hex;
    if (value.startsWith('0x')) {
      hex = value.substring(2).toLowerCase();
    } else {
      final tick = value.indexOf("'h");
      if (tick >= 0) {
        hex = value.substring(tick + 2).toLowerCase();
      } else {
        hex = value.toLowerCase();
      }
    }
    final nibbles = (width + 3) ~/ 4;
    return hex.padLeft(nibbles, '0');
  }

  /// Helper: evaluate a signal in the Inner3D module context.
  ({String value, int width})? eval(
    String signalName, {
    required Map<String, String> snapshot,
  }) {
    // The evaluator expects a full rerooted path: instancePath/signalName
    // but _resolveModulePath peels off segments to find the module def.
    // For a cell "Inner3D" of type "Inner3D" inside Top3D, the path is
    // "Top3D/Inner3D/signalName".
    final path = 'Inner3D/$signalName';
    return evaluateSignalOnDemand(
      modules: modules,
      rerootedPath: path,
      snapshotLookup: (fullPath) => snapshot[fullPath],
    );
  }

  test('evaluator resolves 3D array sub-elements transitively', () {
    // Drive with a known value: 24 bytes = 192 bits.
    // Byte layout (LSB-first):  [0x01, 0x02, ..., 0x18]
    // data = 0x181716...030201 (192 bits)
    final bytes = List.generate(24, (i) => i + 1);
    final bigVal =
        bytes.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final fullValue = '0x$bigVal';

    // Snapshot has only the full port value (what the server provides).
    final snapshot = <String, String>{'Inner3D/data': fullValue};

    // Level 1: data[0] (96 bits = first 12 bytes), data[1] (next 12 bytes)
    final r0 = eval('data[0]', snapshot: snapshot);
    expect(r0, isNotNull, reason: 'data[0] should be evaluable');
    expect(r0!.width, 96);
    // data[0] = bytes[0..11] = 0c0b0a090807060504030201
    expect(hexOf(r0.value, 96), '0c0b0a090807060504030201');

    final r1 = eval('data[1]', snapshot: snapshot);
    expect(r1, isNotNull, reason: 'data[1] should be evaluable');
    expect(r1!.width, 96);
    // data[1] = bytes[12..23] = upper 96 bits
    expect(
      hexOf(r1.value, 96).contains('x'),
      isFalse,
      reason: 'data[1] should not contain x',
    );
    expect(hexOf(r1.value, 96), '1817161514131211100f0e0d');

    // Level 2: data[0][0] (32 bits = 4 bytes), data[0][1] (32 bits)
    final r00 = eval('data[0][0]', snapshot: snapshot);
    expect(r00, isNotNull, reason: 'data[0][0] should be evaluable');
    expect(r00!.width, 32);
    // data[0][0] = bytes[0..3] = 04030201
    expect(hexOf(r00.value, 32), '04030201');

    final r01 = eval('data[0][1]', snapshot: snapshot);
    expect(r01, isNotNull, reason: 'data[0][1] should be evaluable');
    expect(r01!.width, 32);
    // data[0][1] = bytes[4..7] = 08070605
    expect(hexOf(r01.value, 32), '08070605');

    // Level 3: data[0][0][0] (8 bits), data[0][0][1], etc.
    final r000 = eval('data[0][0][0]', snapshot: snapshot);
    expect(r000, isNotNull, reason: 'data[0][0][0] should be evaluable');
    expect(r000!.width, 8);
    // data[0][0][0] = byte[0] = 01
    expect(hexOf(r000.value, 8), '01');

    final r001 = eval('data[0][0][1]', snapshot: snapshot);
    expect(r001, isNotNull, reason: 'data[0][0][1] should be evaluable');
    expect(r001!.width, 8);
    expect(hexOf(r001.value, 8), '02');

    final r012 = eval('data[0][1][2]', snapshot: snapshot);
    expect(r012, isNotNull, reason: 'data[0][1][2] should be evaluable');
    expect(r012!.width, 8);
    // data[0][1][2] = element [0][1][2] = byte index 4+2 = 6 → 07
    expect(hexOf(r012.value, 8), '07');

    final r123 = eval('data[1][2][3]', snapshot: snapshot);
    expect(r123, isNotNull, reason: 'data[1][2][3] should be evaluable');
    expect(r123!.width, 8);
    // data[1][2][3] = element [1][2][3] = byte index 12 + 8 + 3 = 23 → 18
    expect(hexOf(r123.value, 8), '18');
  });

  test('isComputed returns true for 3D array sub-elements', () {
    expect(evaluator.isComputed('Inner3D/data[0][0][0]'), isTrue);
    expect(evaluator.isComputed('Inner3D/data[0][1]'), isTrue);
    expect(evaluator.isComputed('Inner3D/data[1][2][3]'), isTrue);
    expect(evaluator.signalWidth('Inner3D/data[1][2][3]'), 8);
    expect(evaluator.collectLeaves('Inner3D/data[1][2][3]'),
        contains('Inner3D/data'));
    expect(
      evaluator.allEvaluablePaths('Top3D'),
      contains('Top3D/Inner3D/data[1][2][3]'),
    );
  });
}
