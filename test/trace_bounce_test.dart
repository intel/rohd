/// Copyright (C) 2022-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// trace_bounce_test.dart
///
/// 2022 March 4
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(Logic a) : super(name: 'topmodule') {
    a = addInput('a_top', a);
    final bundle = addOutput('bundle_top', width: 3);
    bundle <= SubModule(a).bundle;
  }
}

class SubModule extends Module {
  Logic get bundle => output('bundle');
  SubModule(Logic a) : super(name: 'submodule') {
    a = addInput('a', a);
    final b = addOutput('b');
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');
    final bundle = addOutput('bundle', width: 3);

    b <= a;
    c <= b;
    d <= (Logic()..gets(b));
    e <= ~b;
    bundle <= [c, d, e].swizzle();
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('out depends on out', () async {
    final mod = TopModule(Logic());
    await mod.build();

    final vectors = [
      Vector({'a_top': 0}, {'bundle_top': 1}),
      Vector({'a_top': 1}, {'bundle_top': 6}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });
}
