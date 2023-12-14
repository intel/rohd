// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_merging_test.dart
// Unit tests for deduplication of module definitions in generated verilog
//
// 2023 November 28
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class ComplicatedLeaf extends Module {
  Logic get d => output('d');
  ComplicatedLeaf(
    Logic clk,
    Logic reset, {
    required Logic a,
    required Logic b,
    required Logic c,
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    a = addInput('a', a);
    b = addInput('b', b);
    c = addInput('c', c);

    final internal1 = Logic(name: 'internal1');
    final internal2 = Logic(name: 'internal2');

    addOutput('d');

    Combinational.ssa((s) => [
          s(internal1) < internal2,
          If(a, then: [
            internal1.incr(s: s),
          ]),
          If(b, then: [
            internal1.decr(s: s),
          ]),
          If(c, then: [
            s(internal1) < 0,
          ])
        ]);

    Sequential(clk, reset: reset, [
      internal2 < internal1,
    ]);
  }
}

class TrunkWithLeaves extends Module {
  TrunkWithLeaves(
    Logic clk,
    Logic reset,
  ) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    final abc = [Logic(name: 'a'), Logic(name: 'b'), Logic(name: 'c')];
    for (var i = 0; i < 50; i++) {
      ComplicatedLeaf(
        clk,
        reset,
        a: abc[i % 3],
        b: abc[(i + 1) % 3],
        c: abc[(i + 2) % 3],
      );
    }
  }
}

class SpecificallyDefinedNameModule extends Module {
  SpecificallyDefinedNameModule(Logic a, {required super.definitionName})
      : super(reserveDefinitionName: true) {
    a = addInput('a', a);
    addOutput('b') <= ~a;
  }
}

class ParentOfDifferentModuleDefNames extends Module {
  ParentOfDifferentModuleDefNames(Logic a) {
    a = addInput('a', a);
    SpecificallyDefinedNameModule(a, definitionName: 'def1');
    SpecificallyDefinedNameModule(a, definitionName: 'def2');
  }
}

void main() async {
  test('complex trunk with leaves doesnt duplicate identical modules',
      () async {
    final dut = TrunkWithLeaves(Logic(), Logic());
    await dut.build();
    final sv = dut.generateSynth();

    expect('module ComplicatedLeaf'.allMatches(sv).length, 1);
  });

  test('different reserved definition name modules stay separate', () async {
    final dut = ParentOfDifferentModuleDefNames(Logic());
    await dut.build();
    final sv = dut.generateSynth();

    expect(sv, contains('module def1'));
    expect(sv, contains('module def2'));
  });
}
