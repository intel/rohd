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
  Doublesync(Logic clk, Logic dds) : super(name: 'doublesync') {
    clk = addInput('clk', clk);
    dds = addInput('dds', dds, width: dds.width);
    addOutput('dso', width: dds.width);

    dso <= FlipFlop(clk, FlipFlop(clk, dds, name: 'innerflop').q).q;
  }
}

class DSWrap extends Module {
  Logic get sigSyncWrap => output('sig_sync_wrap');
  DSWrap(Logic clk, Logic sig) : super(name: 'dswrap') {
    sig = addInput('sig', sig);
    clk = addInput('clk', clk);
    addOutput('sig_sync_wrap');
    sigSyncWrap <= Doublesync(clk, sig).dso;
  }
}

class TopModule extends Module {
  TopModule(Logic sig) : super(name: 'top') {
    sig = addInput('sig', sig);
    final sigSync = addOutput('sig_sync');
    sigSync <= DSWrap(SimpleClockGenerator(10).clk, sig).sigSyncWrap;
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
  });
}
