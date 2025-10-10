// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// comb_mod_test.dart
// Unit tests related to Combinationals and other Modules.
//
// 2022 September 26
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class IncrModule extends Module {
  Logic get result => output('result');
  IncrModule(Logic toIncr) : super(name: 'incr') {
    toIncr = addInput('toIncr', toIncr, width: toIncr.width);
    addOutput('result', width: toIncr.width);
    result <= toIncr + 1;
  }
}

class ReuseExample extends Module {
  ReuseExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    final inc = IncrModule(intermediate);

    Combinational([
      intermediate < a,
      intermediate < inc.result,
      intermediate < inc.result,
    ]);

    b <= intermediate;
  }
}

class ReuseExampleSsa extends Module {
  ReuseExampleSsa(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    final inc = IncrModule(intermediate);

    Combinational.ssa((s) => [
          s(intermediate) < a,
          s(intermediate) < inc.result,
          s(intermediate) < inc.result,
        ]);

    b <= intermediate;
  }
}

class DuplicateExample extends Module {
  DuplicateExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    Combinational([
      intermediate < a,
      intermediate < IncrModule(intermediate).result,
      intermediate < IncrModule(intermediate).result,
    ]);

    b <= intermediate;
  }
}

class DuplicateExampleSsa extends Module {
  DuplicateExampleSsa(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    Combinational.ssa((s) => [
          s(intermediate) < a,
          s(intermediate) < IncrModule(s(intermediate)).result,
          s(intermediate) < IncrModule(s(intermediate)).result,
        ]);

    b <= intermediate;
  }
}

class SingleReadAndWriteRf extends Module {
  SingleReadAndWriteRf(
      {required Logic reset,
      required Logic writeEn,
      required Logic writeData,
      required Logic writeAddr,
      required Logic readEn,
      required Logic readAddr,
      bool useSsa = false})
      : super(name: 'singlereadandwriterf') {
    final clk = SimpleClockGenerator(10).clk;

    const numEntries = 16;
    const dataWidth = 8;
    const addrWidth = 4;

    reset = addInput('reset', reset);
    writeEn = addInput('writeEn', writeEn);
    writeData = addInput('writeData', writeData, width: dataWidth);
    writeAddr = addInput('writeAddr', writeAddr, width: addrWidth);
    readEn = addInput('readEn', readEn);
    readAddr = addInput('readAddr', readAddr, width: addrWidth);

    final readData = addOutput('readData', width: dataWidth);

    final storageBank = List<Logic>.generate(
        numEntries, (i) => Logic(name: 'storageBank_$i', width: dataWidth));

    final internalReadEn = Logic(name: 'internalReadEn');
    final internalReadAddr = Logic(name: 'internalReadAddr', width: addrWidth);
    final internalReadData = Logic(name: 'internalReadData', width: dataWidth);

    Sequential(clk, [
      If(reset, then: [
        ...storageBank.map((e) => e < 0)
      ], orElse: [
        for (var entry = 0; entry < numEntries; entry++)
          If(writeEn & writeAddr.eq(entry), then: [
            storageBank[entry] < writeData,
          ]),
      ]),
    ]);

    Combinational(name: 'rf_read', [
      If(~internalReadEn, then: [
        internalReadData < Const(0, width: dataWidth)
      ], orElse: [
        Case(internalReadAddr, [
          for (var entry = 0; entry < numEntries; entry++)
            CaseItem(Const(LogicValue.ofInt(entry, addrWidth)),
                [internalReadData < storageBank[entry]])
        ], defaultItem: [
          internalReadData < Const(0, width: dataWidth)
        ])
      ])
    ]);

    if (useSsa) {
      Combinational.ssa(
          name: 'accessor',
          (s) => [
                readData < 0,
                s(internalReadEn) < 0,
                If(readEn, then: [
                  s(internalReadEn) < readEn,
                  internalReadAddr < readAddr,
                  readData < internalReadData,
                ])
              ]);
    } else {
      Combinational(name: 'accessor', [
        readData < 0,
        internalReadEn < 0,
        If(readEn, then: [
          internalReadEn < readEn,
          internalReadAddr < readAddr,
          readData < internalReadData,
        ])
      ]);
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simulatenous read and write rf', () {
    for (final useSsa in [false, true]) {
      test('useSsa = $useSsa', () async {
        final dut = SingleReadAndWriteRf(
            reset: Logic(),
            writeEn: Logic(),
            writeData: Logic(width: 8),
            writeAddr: Logic(width: 4),
            readEn: Logic(),
            readAddr: Logic(width: 4),
            useSsa: useSsa);

        await dut.build();

        final vectors = [
          Vector({
            'reset': 1,
            'writeEn': 0,
            'writeData': 0,
            'writeAddr': 0,
            'readEn': 0,
            'readAddr': 0
          }, {}),
          Vector({
            'reset': 0,
            'writeEn': 0,
            'writeData': 0,
            'writeAddr': 0,
            'readEn': 1,
            'readAddr': 3
          }, {
            'readData': 0
          }),
          Vector({
            'reset': 0,
            'writeEn': 1,
            'writeData': 5,
            'writeAddr': 3,
            'readEn': 1,
            'readAddr': 3
          }, {
            'readData': 0
          }),
          Vector({
            'reset': 0,
            'writeEn': 0,
            'writeData': 0,
            'writeAddr': 0,
            'readEn': 1,
            'readAddr': 3
          }, {
            'readData': 5
          }),
        ];

        if (useSsa) {
          await SimCompare.checkFunctionalVector(dut, vectors);
          SimCompare.checkIverilogVector(dut, vectors);
        } else {
          try {
            await SimCompare.checkFunctionalVector(dut, vectors);
            fail('Expected a write after read exception!');
          } on Exception catch (e) {
            expect(e, isA<WriteAfterReadException>());
            expect(e.toString(), contains('internalReadEn '));
          }
        }
      });
    }
  });

  group('module reuse', () {
    test('should fail normally', () async {
      try {
        final mod = ReuseExample(Logic(width: 8));
        await mod.build();

        final vectors = [
          Vector({'a': 3}, {'b': 5}) // apply twice (SV behavior)
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('should generate X with combo loop with ssa', () async {
      final mod = ReuseExampleSsa(Logic(width: 8));
      await mod.build();

      final vectors = [
        Vector({'a': 3}, {'b': LogicValue.x})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('module duplicate assignment', () {
    final vectors = [
      Vector({'a': 3}, {'b': 5})
    ];

    test('should fail normally', () async {
      try {
        final mod = DuplicateExample(Logic(width: 8));
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('should apply twice with ssa', () async {
      final mod = DuplicateExampleSsa(Logic(width: 8));
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });
}
