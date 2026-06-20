// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_name_parity_test.dart
// Tests that verify canonicalNameOf works consistently across
// different synthesis paths (SV and netlist).
//
// 2026 April 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/filter_bank.dart';

class _Counter extends Module {
  _Counter(Logic en, Logic reset, {int width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    final val = addOutput('val', width: width);
    final nextVal = Logic(name: 'nextVal', width: width);
    nextVal <= val + 1;
    Sequential.multi(
      [SimpleClockGenerator(10).clk, reset],
      [
        If(
          reset,
          then: [val < 0],
          orElse: [
            If(en, then: [val < nextVal]),
          ],
        ),
      ],
    );
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  group('canonicalNameOf after netlist synthesis', () {
    test('counter — returns names after netlist synthesis', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();
      NetlistService(mod);

      expect(mod.namer.signalNameOf(mod.input('en')), equals('en'));
      expect(mod.namer.signalNameOf(mod.input('reset')), equals('reset'));
      expect(mod.namer.signalNameOf(mod.output('val')), equals('val'));
    });

    test('filter_bank — returns names for sub-module signals', () async {
      const dataWidth = 16;
      const numTaps = 3;
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final start = Logic(name: 'start');
      final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
      final inputDone = Logic(name: 'inputDone');

      final dut = FilterBank(
        clk,
        reset,
        start,
        samples,
        inputDone,
        numTaps: numTaps,
        dataWidth: dataWidth,
        coefficients: [
          [1, 2, 1],
          [1, -2, 1],
        ],
      );
      await dut.build();
      NetlistService(dut);

      expect(dut.namer.signalNameOf(dut.input('clk')), equals('clk'));
      expect(dut.namer.signalNameOf(dut.input('reset')), equals('reset'));
      expect(dut.namer.signalNameOf(dut.output('done')), equals('done'));
    });
  });

  group('canonicalNameOf after SV synthesis', () {
    test('counter — returns canonical name after SV synth', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      SvService(mod, register: false).synthOutput;

      expect(mod.namer.signalNameOf(mod.input('en')), equals('en'));
      expect(mod.namer.signalNameOf(mod.input('reset')), equals('reset'));
    });
  });

  group('cross-synthesizer parity', () {
    test(
      'counter — SV and netlist produce identical canonicalNameOf',
      () async {
        final modNetlist = _Counter(Logic(), Logic());
        await modNetlist.build();
        NetlistService(modNetlist);
        await Simulator.reset();

        final modSv = _Counter(Logic(), Logic());
        await modSv.build();
        SvService(modSv, register: false).synthOutput;

        // Both paths use the same Namer, so names must match.
        final enNetlist = modNetlist.namer.signalNameOf(modNetlist.input('en'));
        final enSv = modSv.namer.signalNameOf(modSv.input('en'));

        expect(
          enSv,
          equals(enNetlist),
          reason: 'SV and netlist should produce identical canonical names',
        );
      },
    );
  });
}
