// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Test: 3D LogicArray transitive evaluation via the netlist evaluator.
//
// Verifies that `evaluateSignalOnDemand` correctly resolves inner-dimension
// array element signals that do NOT have explicit $slice cells (only the
// outermost dimension gets $slice cells from `_subsetReceiveArrayPort`).
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

    // Level 1: data_0_ (96 bits = first 12 bytes), data_1_ (next 12 bytes)
    final r0 = eval('data_0_', snapshot: snapshot);
    expect(r0, isNotNull, reason: 'data_0_ should be evaluable');
    expect(r0!.width, 96);
    // data_0_ = bytes[0..11] = 0c0b0a090807060504030201
    expect(hexOf(r0.value, 96), '0c0b0a090807060504030201');

    final r1 = eval('data_1_', snapshot: snapshot);
    expect(r1, isNotNull, reason: 'data_1_ should be evaluable');
    expect(r1!.width, 96);
    // data_1_ = bytes[12..23] = upper 96 bits
    expect(
      hexOf(r1.value, 96).contains('x'),
      isFalse,
      reason: 'data_1_ should not contain x',
    );
    expect(hexOf(r1.value, 96), '1817161514131211100f0e0d');

    // Level 2: data_0__0_ (32 bits = 4 bytes), data_0__1_ (32 bits)
    final r00 = eval('data_0__0_', snapshot: snapshot);
    expect(r00, isNotNull, reason: 'data_0__0_ should be evaluable');
    expect(r00!.width, 32);
    // data_0__0_ = bytes[0..3] = 04030201
    expect(hexOf(r00.value, 32), '04030201');

    final r01 = eval('data_0__1_', snapshot: snapshot);
    expect(r01, isNotNull, reason: 'data_0__1_ should be evaluable');
    expect(r01!.width, 32);
    // data_0__1_ = bytes[4..7] = 08070605
    expect(hexOf(r01.value, 32), '08070605');

    // Level 3: data_0__0__0_ (8 bits), data_0__0__1_, etc.
    final r000 = eval('data_0__0__0_', snapshot: snapshot);
    expect(r000, isNotNull, reason: 'data_0__0__0_ should be evaluable');
    expect(r000!.width, 8);
    // data_0__0__0_ = byte[0] = 01
    expect(hexOf(r000.value, 8), '01');

    final r001 = eval('data_0__0__1_', snapshot: snapshot);
    expect(r001, isNotNull, reason: 'data_0__0__1_ should be evaluable');
    expect(r001!.width, 8);
    expect(hexOf(r001.value, 8), '02');

    final r012 = eval('data_0__1__2_', snapshot: snapshot);
    expect(r012, isNotNull, reason: 'data_0__1__2_ should be evaluable');
    expect(r012!.width, 8);
    // data_0__1__2_ = element [0][1][2] = byte index 4+2 = 6 → 07
    expect(hexOf(r012.value, 8), '07');

    final r123 = eval('data_1__2__3_', snapshot: snapshot);
    expect(r123, isNotNull, reason: 'data_1__2__3_ should be evaluable');
    expect(r123!.width, 8);
    // data_1__2__3_ = element [1][2][3] = byte index 12 + 8 + 3 = 23 → 18
    expect(hexOf(r123.value, 8), '18');
  });

  test('isComputed returns true for 3D array sub-elements', () {
    // data_0__0__0_ should be recognized as computed (array element pattern)
    expect(evaluator.isComputed('Inner3D/data_0__0__0_'), isTrue);
    expect(evaluator.isComputed('Inner3D/data_0__1_'), isTrue);
    expect(evaluator.isComputed('Inner3D/data_1__2__3_'), isTrue);
  });
}
