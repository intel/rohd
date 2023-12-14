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
  AlphabeticalModule(Logic l, Logic a, Logic w) {
    l = addInput('l', l);
    a = addInput('a', a);
    w = addInput('w', w);

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

class AlphabeticalSubmodulePorts extends Module {
  AlphabeticalSubmodulePorts() {
    final l = addInput('l', Logic());
    final a = addInput('a', Logic());
    final w = addInput('w', Logic());

    final am = AlphabeticalModule(l, a, w);

    addOutput('m') <= am.output('m');
    addOutput('x') <= am.output('x');
    addOutput('b') <= am.output('b');
  }
}

class TopWithExpressions extends Module {
  TopWithExpressions(Logic a, Logic b) {
    a = addInput('a', a);
    b = addInput('b', b, width: 5);

    addOutput('o') <= SubForExpressions(a | b[2]).o;
  }
}

class SubForExpressions extends Module {
  Logic get o => output('o');
  SubForExpressions(Logic a) {
    a = addInput('a', a);
    addOutput('o') <= a;
  }
}

class ModuleWithFloatingSignals extends Module {
  ModuleWithFloatingSignals() {
    final a = addInput('apple', Logic());
    addOutput('orange');

    final s = Logic(name: 'squash', naming: Naming.reserved);

    Logic(name: 'xylophone') <= a | s;
  }
}

void main() {
  group('signal declaration order', () {
    void checkSignalDeclarationOrder(String sv, List<String> signalNames) {
      final expected =
          signalNames.map((e) => RegExp(r'logic\s*\[?[:\d\s]*]?\s*' + e));
      final indices = expected.map(sv.indexOf);
      expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
          reason: 'Expected order $signalNames, but indices were $indices');
    }

    test('input, output, and internal signals are sorted', () async {
      final mod = AlphabeticalModule(Logic(), Logic(), Logic());
      await mod.build();
      final sv = mod.generateSynth();

      // as instantiated
      checkSignalDeclarationOrder(sv, ['l', 'a', 'w']);
      checkSignalDeclarationOrder(sv, ['m', 'x', 'b']);

      // alphabetized
      checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);

      checkSignalDeclarationOrder(
          sv, ['l', 'a', 'w', 'm', 'x', 'b', 'c', 'o', 'y']);
    });

    test('input, output, and internal signals are sorted (different widths)',
        () async {
      final mod = AlphabeticalWidthsModule();
      await mod.build();
      final sv = mod.generateSynth();

      // as instantiated
      checkSignalDeclarationOrder(sv, ['l', 'a', 'w']);
      checkSignalDeclarationOrder(sv, ['m', 'x', 'b']);

      // alphabetized
      checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);

      checkSignalDeclarationOrder(
          sv, ['l', 'a', 'w', 'm', 'x', 'b', 'c', 'o', 'y']);
    });
  });

  test(
      'submodule port connections input, '
      'output are sorted by declaration order', () async {
    void checkPortConnectionOrder(String sv, List<String> signalNames) {
      final expected = signalNames.map((e) => '.$e($e)');
      final indices = expected.map(sv.indexOf);
      expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
          reason: 'Expected order $signalNames, but indices were $indices');
    }

    final mod = AlphabeticalSubmodulePorts();
    await mod.build();
    final sv = mod.generateSynth();

    checkPortConnectionOrder(sv, ['l', 'a', 'w', 'm', 'x', 'b']);
  });

  test('expressions in sub-module declaration', () async {
    final mod = TopWithExpressions(Logic(), Logic(width: 5));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('.a((a | (b[2])))'));
  });

  test('no floating assignments', () async {
    final mod = ModuleWithFloatingSignals();
    await mod.build();

    final sv = mod.generateSynth();

    // only expect 1 assignment to xylophone
    expect('assign'.allMatches(sv).length, 1);
    expect('assign xylophone'.allMatches(sv).length, 1);
  });
}
