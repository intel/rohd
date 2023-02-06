/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// translations_test.dart
/// Unit tests looking at redoing some real implementations in a better way
///
/// 2021 May 20
/// Author: Max Korbel <max.korbel@intel.com>
///

// ignore_for_file: avoid_multiple_declarations_per_line

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class FlopArrayPort {
  final Logic en, ptr, data;
  FlopArrayPort(this.en, this.ptr, this.data);
}

class FlopArray extends Module {
  // for convenience, make it easier to access inputs and outputs of this module
  Logic get lclk => input('lclk');
  Logic get lrst => input('lrst');
  Logic rdData(int idx) => _rdPorts[idx].data;

  final List<FlopArrayPort> _wrPorts = [], _rdPorts = [];

  final int numWrites, numReads, awidth, dwidth, numEntries;
  FlopArray(Logic lclk, Logic lrst, List<Logic> rdEn, List<Logic> rdPtr,
      List<Logic> wrEn, List<Logic> wrPtr, List<Logic> wrData,
      {this.numEntries = 8})
      : numWrites = wrEn.length,
        numReads = rdEn.length,
        dwidth = wrData[0].width,
        awidth = rdPtr[0].width,
        super(name: 'floparray_${wrEn.length}w_${rdEn.length}r') {
    // make sure widths of everything match expectations
    if (rdPtr.length != numReads) {
      throw Exception('Read pointer length must match number of read enables.');
    }
    if (wrPtr.length != numWrites) {
      throw Exception(
          'Write pointer length must match number of write enables');
    }
    if (wrData.length != numWrites) {
      throw Exception('Write data length must match number of write enables');
    }

    // register inputs and outputs with ROHD
    addInput('lclk', lclk);
    addInput('lrst', lrst);
    for (var i = 0; i < numReads; i++) {
      _rdPorts.add(FlopArrayPort(
          addInput('rdEn$i', rdEn[i]),
          addInput('rdPtr$i', rdPtr[i], width: awidth),
          addOutput('rdData$i', width: dwidth)));
    }
    for (var i = 0; i < numWrites; i++) {
      _wrPorts.add(FlopArrayPort(
          addInput('wrEn$i', wrEn[i]),
          addInput('wrPtr$i', wrPtr[i], width: awidth),
          addInput('wrData$i', wrData[i], width: dwidth)));
    }

    _buildLogic();
  }

  void _buildLogic() {
    // create local storage bank
    final storageBank = List<Logic>.generate(
        numEntries, (i) => Logic(name: 'storageBank_$i', width: dwidth));

    // Sequential(lclk, [  // normally this should be here
    Sequential(SimpleClockGenerator(10).clk, [
      //for testing purposes, easier to just plug a clock in here
      If(lrst, then: [
        ...storageBank
            .map((e) => e < 0) // zero out entire storage bank on reset
      ], orElse: [
        ...List.generate(
            numEntries,
            (entry) => [
                  ..._wrPorts.map((wrPort) =>
                      // set storage bank if write enable and pointer matches
                      If(wrPort.en & wrPort.ptr.eq(entry),
                          then: [storageBank[entry] < wrPort.data])),
                  ..._rdPorts.map((rdPort) =>
                      // read storage bank if read enable and pointer matches
                      If(rdPort.en & rdPort.ptr.eq(entry),
                          then: [rdPort.data < storageBank[entry]])),
                ]).expand((e) => e) // flatten
      ]),
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('translation', () async {
      const numRdPorts = 2;
      const numWrPorts = 2;
      final ftm = FlopArray(
        Logic(),
        Logic(),
        List<Logic>.generate(numRdPorts, (index) => Logic()),
        List<Logic>.generate(numRdPorts, (index) => Logic(width: 6)),
        List<Logic>.generate(numWrPorts, (index) => Logic()),
        List<Logic>.generate(numWrPorts, (index) => Logic(width: 6)),
        List<Logic>.generate(numWrPorts, (index) => Logic(width: 16)),
      );
      await ftm.build();
      // File('tmp.sv').writeAsStringSync(ftm.generateSynth())
      // WaveDumper(ftm);
      final vectors = [
        Vector({'lrst': 0}, {}),
        Vector({'lrst': 1}, {}),
        Vector({'lrst': 1, 'wrEn0': 0, 'rdEn0': 0, 'wrEn1': 0, 'rdEn1': 0}, {}),
        Vector({'lrst': 0}, {}),
        Vector({'wrEn1': 1, 'wrPtr1': 4, 'wrData1': 0xf}, {}),
        Vector({'wrEn1': 0, 'rdEn0': 1, 'rdPtr0': 4}, {}),
        Vector({'wrEn1': 0, 'rdEn0': 0}, {'rdData0': 0xf}),
      ];
      await SimCompare.checkFunctionalVector(ftm, vectors);
      final simResult = SimCompare.iverilogVector(ftm, vectors);
      expect(simResult, equals(true));
    });
  });
}
