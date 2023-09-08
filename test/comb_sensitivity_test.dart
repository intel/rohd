// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// comb_sensitivity_test.dart
// Unit tests related to Combinational sensitivities.
//
// 2022 December 22
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SeqWrapper extends Module {
  Logic get fromFlop => output('fromFlop');
  SeqWrapper(Logic toFlop, Logic toNothing, {Logic? en}) {
    toFlop = addInput('toFlop', toFlop);
    toNothing = addInput('toNothing', toNothing);

    addOutput('fromFlop');

    if (en != null) {
      en = addInput('en', en);
      fromFlop <=
          FlipFlop(
            SimpleClockGenerator(10).clk,
            toFlop,
            en: en,
          ).q;
    } else {
      fromFlop <=
          FlipFlop(
            SimpleClockGenerator(10).clk,
            toFlop,
          ).q;
    }
  }
}

class TopMod extends Module {
  Logic get muxToFlop => output('muxToFlop');
  TopMod(Logic theSource, {Logic? en}) {
    theSource = addInput('theSource', theSource);

    final control = Logic(name: 'control');
    final toNothing = Logic(name: 'toNothing');

    final toFlop = mux(
      control,
      Const(0),
      theSource,
    );

    final SeqWrapper seqWrapper;
    if (en != null) {
      seqWrapper = SeqWrapper(toFlop, toNothing, en: en);
    } else {
      seqWrapper = SeqWrapper(toFlop, toNothing);
    }

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

  test('false sensitivity does not cause false comb cycle (test with enable 1)',
      () async {
    final theSource = Logic(name: 'theSource')..put(0);
    final en = Logic(name: 'en')..put(1);
    final mod = TopMod(theSource, en: en);

    await mod.build();

    theSource.put(1);

    expect(mod.muxToFlop.value.isValid, isTrue);
  });

  test('false sensitivity does not cause false comb cycle (test with enable 0)',
      () async {
    final theSource = Logic(name: 'theSource')..put(0);
    final en = Logic(name: 'en')..put(0);
    final mod = TopMod(theSource, en: en);

    await mod.build();

    theSource.put(1);

    expect(mod.muxToFlop.value.isValid, isTrue);
  });
}
