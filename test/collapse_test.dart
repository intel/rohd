/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// collapse_test.dart
/// Unit tests for collapsing systemverilog to a smaller representation
///
/// 2021 July 14
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class CollapseTestModule extends Module {
  Logic get a => input('a');
  Logic get b => input('b');

  CollapseTestModule(Logic a, Logic b) : super(name: 'collapsetestmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final c = addOutput('c');
    final d = addOutput('d');
    final e = addOutput('e');
    final f = addOutput('f');

    final x = Logic(name: 'x');
    final y = Logic(name: 'y');
    final z = Logic(name: 'z');
    c <= a & b;
    d <= a & b;
    x <= a;
    y <= x;
    e <= a & b & c & x & y;
    z <= b & y;
    f <= a & z;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('collapse functional', () async {
    final mod = CollapseTestModule(Logic(), Logic());
    await mod.build();
    final vectors = [
      Vector({'a': 1, 'b': 1}, {'c': 1, 'd': 1, 'e': 1, 'f': 1}),
      Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 0, 'e': 0, 'f': 0}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    final simResult = SimCompare.iverilogVector(mod, vectors);
    expect(simResult, equals(true));
  });

  test('collapse pretty', () async {
    final mod = CollapseTestModule(Logic(), Logic());
    await mod.build();
    final synth = mod.generateSynth();

    // File('tmp.sv').writeAsStringSync(synth);
    // print(synth);

    // make sure e=a&b&c is in there, to prove there was some inlining
    expect(synth.contains(RegExp('e.*=.*a.*&.*b.*&.*c')), equals(true));
  });
}
