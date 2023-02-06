/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule4_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple instantiation
/// (another type)
///
/// 2021 June 30
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:test/test.dart';

// mostly all inputs
class InnerModule2 extends Module {
  Logic get z => output('z');
  InnerModule2() : super(name: 'innermodule2') {
    addOutput('z');
    z <= Const(1);
  }
}

class InnerModule1 extends Module {
  InnerModule1(Logic y) : super(name: 'innermodule1') {
    y = addInput('y', y);
    final m = Logic();
    m <= Passthrough(InnerModule2().z).out | y;
  }
}

class TopModule extends Module {
  TopModule(Logic x) : super(name: 'topmod') {
    x = addInput('x', x);
    InnerModule1(x);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('multimodules4', () async {
    final ftm = TopModule(Logic());
    await ftm.build();

    // find a module with 'z' output 2 levels deep
    assert(
        ftm.subModules
            .where((pIn1) => pIn1.subModules
                .where((pIn2) => pIn2.outputs.containsKey('z'))
                .isNotEmpty)
            .isNotEmpty,
        'Should find a z two levels deep');

    final synth = ftm.generateSynth();

    // "z = 1" means it correctly traversed down from inputs
    assert(synth.contains('z = 1'),
        'Should correctly traverse from inputs to z=1');

    // print(ftm.hierarchy());
    // File('tmp4.sv').writeAsStringSync(synth);
  });
}
