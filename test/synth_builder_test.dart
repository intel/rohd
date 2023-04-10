/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synth_builder_test.dart
/// Unit tests for generation of the system verilog using synth builder.
///
/// 2023 April 10
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
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
      final mod = TopModule(Logic(width: 4), Logic());

      final bmod = BModule(Logic());
      await bmod.build();

      final syn = SynthBuilder(bmod, SystemVerilogSynthesizer());

      print(syn.toString());

      // expect(simResult, equals(true));
    });
  });
}
