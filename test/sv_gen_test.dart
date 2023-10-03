// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_gen_test.dart
// Tests for SystemVerilog generation.
//
// 2023 October 4
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class AlphabeticalModule extends Module {
  AlphabeticalModule() {
    final l = addInput('l', Logic());
    final a = addInput('a', Logic());
    final w = addInput('w', Logic());

    final o = Logic(name: 'o');
    final c = Logic(name: 'c');
    final y = Logic(name: 'y');

    c <= l & w;
    o <= a | l;
    y <= w ^ l;

    addOutput('m');
    addOutput('x') <= c + o + y;
    addOutput('b');
  }
}

void main() {
  test('input, output, and internal signals are sorted', () async {
    final mod = AlphabeticalModule();
    await mod.build();
    final sv = mod.generateSynth();

    void checkSignalDeclarationOrder(List<String> signalNames) {
      final expected = signalNames.map((e) => 'logic $e');
      final indices = expected.map(sv.indexOf);
      expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
          reason: 'Expected order $expected, but indices were $indices');
    }

    checkSignalDeclarationOrder(['a', 'l', 'w']);
    checkSignalDeclarationOrder(['b', 'm', 'x']);
    checkSignalDeclarationOrder(['c', 'o', 'y']);
  });
}
