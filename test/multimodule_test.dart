/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple instantiation
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(Logic a, Logic b) : super(name: 'topmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final y = addOutput('y', width: a.width);
    final z = addOutput('z', width: b.width);
    final z2 = addOutput('z2', width: b.width);

    y <= AModule(a).y;
    z <= BModule(b).zz;
    z2 <= BModule(b).zz;
  }
}

class AModule extends Module {
  Logic get y => output('y');

  AModule(Logic a) : super(name: 'amodule') {
    a = addInput('a', a, width: a.width);
    final y = addOutput('y', width: a.width);

    final tmp = Logic(width: a.width);
    y <= tmp;
    tmp <= a;
  }
}

class BModule extends Module {
  Logic get zz => output('zz');
  BModule(Logic bb) : super(name: 'bmodule') {
    bb = addInput('bb', bb, width: bb.width);
    final zz = addOutput('zz', width: bb.width);

    zz <= ~bb;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('multimodules', () async {
      final ftm = TopModule(Logic(width: 4), Logic());
      await ftm.build();
      final vectors = [
        Vector({'a': 0, 'b': 0}, {'y': 0, 'z': 1, 'z2': 1}),
        Vector({'a': 1, 'b': 1}, {'y': 1, 'z': 0, 'z2': 0}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
  });
}
