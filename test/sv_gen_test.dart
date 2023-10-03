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

class AlphabeticalWidthsModule extends Module {
  AlphabeticalWidthsModule() {
    final l = addInput('l', Logic(width: 4), width: 4);
    final a = addInput('a', Logic(width: 3), width: 3);
    final w = addInput('w', Logic(width: 2), width: 2);

    final o = Logic(name: 'o', width: 4);
    final c = Logic(name: 'c', width: 3);
    final y = Logic(name: 'y', width: 2);

    c <= a & a;
    o <= l | l;
    y <= w ^ w;

    addOutput('m', width: 4) <= o + o;
    addOutput('x', width: 2) <= y + y;
    addOutput('b', width: 3) <= c + c;
  }
}

void main() {
  void checkSignalDeclarationOrder(String sv, List<String> signalNames) {
    final expected =
        signalNames.map((e) => RegExp(r'logic\s*\[?[:\d\s]*]?\s*' + e));
    final indices = expected.map(sv.indexOf);
    expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
        reason: 'Expected order $signalNames, but indices were $indices');
  }

  test('input, output, and internal signals are sorted', () async {
    final mod = AlphabeticalModule();
    await mod.build();
    final sv = mod.generateSynth();

    checkSignalDeclarationOrder(sv, ['a', 'l', 'w']);
    checkSignalDeclarationOrder(sv, ['b', 'm', 'x']);
    checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);
  });

  test('input, output, and internal signals are sorted (different widths)',
      () async {
    final mod = AlphabeticalWidthsModule();
    await mod.build();
    final sv = mod.generateSynth();

    checkSignalDeclarationOrder(sv, ['a', 'l', 'w']);
    checkSignalDeclarationOrder(sv, ['b', 'm', 'x']);
    checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);
  });
}
