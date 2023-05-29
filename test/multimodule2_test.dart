/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule2_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple
/// instantiation (another type)
///
/// 2021 June 28
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class Doublesync extends Module {
  Logic get dso => output('dso');
  Doublesync(Logic clk, Logic dds, {Logic? en}) : super(name: 'doublesync') {
    clk = addInput('clk', clk);
    dds = addInput('dds', dds, width: dds.width);

    addOutput('dso', width: dds.width);

    if (en != null) {
      en = addInput('en', en, width: en.width);

      dso <= FlipFlop(clk, FlipFlop(clk, dds, en: en, name: 'innerflop').q).q;
    } else {
      dso <= FlipFlop(clk, FlipFlop(clk, dds, name: 'innerflop').q).q;
    }
  }
}

class DSWrap extends Module {
  Logic get sigSyncWrap => output('sig_sync_wrap');
  DSWrap(Logic clk, Logic sig, {Logic? en}) : super(name: 'dswrap') {
    sig = addInput('sig', sig);
    clk = addInput('clk', clk);
    addOutput('sig_sync_wrap');

    if (en != null) {
      en = addInput('en', en);

      sigSyncWrap <= Doublesync(clk, sig, en: en).dso;
    } else {
      sigSyncWrap <= Doublesync(clk, sig).dso;
    }
  }
}

class TopModule extends Module {
  TopModule(Logic sig, {Logic? en}) : super(name: 'top') {
    sig = addInput('sig', sig);
    final sigSync = addOutput('sig_sync');
    if (en != null) {
      en = addInput('en', en);

      sigSync <= DSWrap(SimpleClockGenerator(10).clk, sig, en: en).sigSyncWrap;
    } else {
      sigSync <= DSWrap(SimpleClockGenerator(10).clk, sig).sigSyncWrap;
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('multimodules2', () async {
      final ftm = TopModule(Logic());
      await ftm.build();
      final vectors = [
        Vector({'sig': 0}, {}),
        Vector({'sig': 0}, {}),
        Vector({'sig': 0}, {}),
        Vector({'sig': 1}, {'sig_sync': 0}),
        Vector({'sig': 1}, {'sig_sync': 0}),
        Vector({'sig': 1}, {'sig_sync': 1}),
        Vector({'sig': 1}, {'sig_sync': 1}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
    test('multimodules2 with enable', () async {
      final ftm = TopModule(Logic(), en: Logic());
      await ftm.build();
      final vectors = [
        Vector({'sig': 0, 'en': 1}, {}),
        Vector({'sig': 0, 'en': 1}, {}),
        Vector({'sig': 0, 'en': 1}, {}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 0}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 0}),
        Vector({'sig': 0, 'en': 0}, {'sig_sync': 1}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 1}),
        Vector({'sig': 0, 'en': 1}, {'sig_sync': 1}),
        Vector({'sig': 0, 'en': 0}, {'sig_sync': 1}),
        Vector({'sig': 1, 'en': 0}, {'sig_sync': 0}),
        Vector({'sig': 1, 'en': 0}, {'sig_sync': 0}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 0}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 0}),
        Vector({'sig': 0, 'en': 1}, {'sig_sync': 1}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 1}),
        Vector({'sig': 1, 'en': 1}, {'sig_sync': 0}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
  });
}
