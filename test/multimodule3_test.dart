/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule3_test.dart
/// Unit tests for a hierarchy of multiple modules and
/// multiple instantiation (another type)
///
/// 2021 June 30
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

// mostly all outputs
class InnerModule2 extends Module {
  Logic get z => output('z');
  InnerModule2() : super(name: 'innermodule2') {
    addOutput('z');
    z <= Const(1);
  }
}

class InnerModule1 extends Module {
  Logic get y => output('y');
  Logic get m => output('m');
  InnerModule1() : super(name: 'innermodule1') {
    addOutput('m');
    m <= Const(0);
    addOutput('y');
    y <= Passthrough(InnerModule2().z).out;
  }
}

class TopModule extends Module {
  Logic get x => output('x');
  TopModule() : super(name: 'topmod') {
    addOutput('x');
    final im1 = InnerModule1();
    x <= im1.y | im1.m;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('multimodules3', () async {
      final ftm = TopModule();
      await ftm.build();
      final vectors = [
        Vector({}, {'x': 1}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
  });
}
