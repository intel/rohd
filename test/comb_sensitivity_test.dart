/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_sensitivity_test.dart
/// Unit tests related to Combinational sensitivities.
///
/// 2022 December 22
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SeqWrapper extends Module {
  Logic get fromFlop => output('fromFlop');
  SeqWrapper(Logic toFlop, Logic toNothing) {
    toFlop = addInput('toFlop', toFlop);
    toNothing = addInput('toNothing', toNothing);

    addOutput('fromFlop');

    fromFlop <=
        FlipFlop(
          SimpleClockGenerator(10).clk,
          toFlop,
        ).q;
  }
}

class TopMod extends Module {
  Logic get muxToFlop => output('muxToFlop');
  TopMod(Logic theSource) {
    theSource = addInput('theSource', theSource);

    final control = Logic(name: 'control');
    final toNothing = Logic(name: 'toNothing');

    final toFlop = mux(
      control,
      Const(0),
      theSource,
    );

    final seqWrapper = SeqWrapper(toFlop, toNothing);

    Combinational([
      control < theSource,
      toNothing < seqWrapper.fromFlop,
    ]);

    addOutput('muxToFlop') <= toFlop;
  }
}

void main() async {
  test('false sensitivity does not cause false comb cycle', () async {
    final theSource = Logic(name: 'theSource')..put(0);

    final mod = TopMod(theSource);

    await mod.build();

    theSource.put(1);

    expect(mod.muxToFlop.value.isValid, isTrue);
  });
}
