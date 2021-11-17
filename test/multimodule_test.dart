/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple instantiation
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class TopModule extends Module {
  TopModule(Logic a, Logic b) : super(name: 'topmodule') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    var y = addOutput('y', width: a.width);
    var z = addOutput('z', width: b.width);
    var z2 = addOutput('z2', width: b.width);

    y <= AModule(a).y;
    z <= BModule(b).zz;
    z2 <= BModule(b).zz;
  }
}

class AModule extends Module {
  Logic get y => output('y');

  AModule(Logic a) : super(name: 'amodule') {
    a = addInput('a', a, width: a.width);
    var y = addOutput('y', width: a.width);

    var tmp = Logic(width: a.width);
    y <= tmp;
    tmp <= a;
  }
}

class BModule extends Module {
  Logic get zz => output('zz');
  BModule(Logic bb) : super(name: 'bmodule') {
    bb = addInput('bb', bb, width: bb.width);
    var zz = addOutput('zz', width: bb.width);

    zz <= ~bb;
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {
    test('multimodules', () async {
      var ftm = TopModule(Logic(width: 4), Logic());
      await ftm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'y': 0, 'z': 1, 'z2': 1}),
        Vector({'a': 1, 'b': 1}, {'y': 1, 'z': 0, 'z2': 0}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      var simResult = SimCompare.iverilogVector(
          ftm.generateSynth(), ftm.runtimeType.toString(), vectors,
          signalToWidthMap: {
            'a': 4,
            'y': 4,
          });
      expect(simResult, equals(true));
    });
  });
}
