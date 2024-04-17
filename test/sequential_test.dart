// SPDX-License-Identifier: BSD-3-Clause
// Copyright (C) 2021-2024 Intel Corporation
//
// sequential_test.dart
// Unit test for Sequential
//
// 2022 January 31
// Substantial portion of test contributed by wswongat in https://github.com/intel/rohd/issues/79
// Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class DelaySignal extends Module {
  Logic get out => output('out');

  final int bitWidth;
  final int depth;

  DelaySignal(Logic en, Logic inputVal,
      {this.bitWidth = 4, this.depth = 5, super.name = 'movingSum'}) {
    en = addInput('en', en);
    inputVal = addInput('inputVal', inputVal, width: bitWidth);
    final clk = SimpleClockGenerator(10).clk;
    final z = List<Logic>.generate(
        depth, (index) => Logic(width: bitWidth, name: 'z$index'));

    final out = addOutput('out', width: bitWidth);

    final zList = <Conditional>[z[0] < inputVal];
    for (var i = 0; i < z.length; i++) {
      if (i == z.length - 1) {
        zList.add(out < z[i]);
      } else {
        zList.add(z[i + 1] < z[i]);
      }
    }

    Sequential(clk, [
      If.block([
        Iff(en, zList),
        Else([
          out < 0,
        ])
      ])
    ]);
  }
}

class ShorthandSeqModule extends Module {
  final bool useArrays;

  @override
  Logic addOutput(String name, {int width = 1}) {
    assert(width.isEven, 'if arrays, split width in 2');
    if (useArrays) {
      return super
          .addOutputArray(name, dimensions: [2], elementWidth: width ~/ 2);
    } else {
      return super.addOutput(name, width: width);
    }
  }

  ShorthandSeqModule(Logic reset,
      {this.useArrays = false,
      int initialVal = 16,
      bool doubleResetError = false})
      : super(name: 'shorthandmodule') {
    reset = addInput('reset', reset);

    final piOut = addOutput('piOut', width: 8);
    final pdOut = addOutput('pdOut', width: 8);
    final maOut = addOutput('maOut', width: 8);
    final daOut = addOutput('daOut', width: 8);

    final clk = SimpleClockGenerator(10).clk;

    Sequential(
      clk,
      [
        piOut.incr(),
        pdOut.decr(),
        maOut.mulAssign(2),
        daOut.divAssign(2),
      ],
      reset: reset,
      resetValues: {
        piOut: initialVal,
        pdOut: initialVal,
        maOut: initialVal,
        daOut: initialVal,
        if (useArrays && doubleResetError) daOut.elements[0]: initialVal,
      },
    );
  }
}

class SeqResetValTypes extends Module {
  SeqResetValTypes(Logic reset, Logic i) : super(name: 'seqResetValTypes') {
    reset = addInput('reset', reset);
    i = addInput('i', i, width: 8);
    final clk = SimpleClockGenerator(10).clk;

    final a = addOutput('a', width: 8); // int
    final b = addOutput('b', width: 8); // LogicValue
    final c = addOutput('c', width: 8); // Logic
    final d = addOutput('d', width: 8); // none

    Sequential(
      clk,
      reset: reset,
      resetValues: {
        a: 7,
        b: LogicValue.ofInt(12, 8),
        c: i,
      },
      [
        a < 8,
        b < LogicValue.ofInt(13, 8),
        c < i + 1,
        d < 4,
      ],
    );
  }
}

class NegedgeTriggeredSeq extends Module {
  NegedgeTriggeredSeq(Logic a) {
    a = addInput('a', a);
    final b = addOutput('b');
    final clk = SimpleClockGenerator(10).clk;

    Sequential.multi(
      [],
      negedgeTriggers: [~clk],
      [b < a],
    );
  }
}

class BothTriggeredSeq extends Module {
  BothTriggeredSeq(Logic reset) {
    reset = addInput('reset', reset);
    final b = addOutput('b', width: 8);
    final clk = SimpleClockGenerator(10).clk;

    Sequential.multi(
      [clk],
      reset: reset,
      negedgeTriggers: [clk],
      [b < b + 1],
    );
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple pipeline', () async {
    final dut = DelaySignal(
      Logic(),
      Logic(width: 4),
    );
    await dut.build();

    final vectors = [
      Vector({'inputVal': 0, 'en': 1}, {}),
      Vector({'inputVal': 1, 'en': 0}, {}),
      Vector({'inputVal': 2, 'en': 0}, {}),
      Vector({'inputVal': 3, 'en': 1}, {}),
      Vector({'inputVal': 4, 'en': 1}, {}),
      Vector({'inputVal': 5, 'en': 1}, {}),
      Vector({'inputVal': 6, 'en': 1}, {}),
      Vector({'inputVal': 7, 'en': 1}, {}),
      Vector({'inputVal': 8, 'en': 1}, {'out': 0}),
      Vector({'inputVal': 9, 'en': 1}, {'out': 3}),
      Vector({}, {'out': 4}),
      Vector({}, {'out': 5}),
    ];
    await SimCompare.checkFunctionalVector(dut, vectors);
    SimCompare.checkIverilogVector(dut, vectors);
  });

  group('shorthand with sequential', () {
    Future<void> testShorthand(
        {required bool useArrays, bool doubleResetError = false}) async {
      final mod = ShorthandSeqModule(Logic(),
          useArrays: useArrays, doubleResetError: doubleResetError);
      await mod.build();

      final vectors = [
        Vector({'reset': 1}, {}),
        Vector(
            {'reset': 1}, {'piOut': 16, 'pdOut': 16, 'maOut': 16, 'daOut': 16}),
        Vector(
            {'reset': 0}, {'piOut': 16, 'pdOut': 16, 'maOut': 16, 'daOut': 16}),
        Vector(
            {'reset': 0}, {'piOut': 17, 'pdOut': 15, 'maOut': 32, 'daOut': 8}),
      ];

      // await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    }

    test('normal logic', () async {
      await testShorthand(useArrays: false);
    });

    test('arrays', () async {
      await testShorthand(useArrays: true);
    });

    test('arrays with double reset error', () async {
      expect(testShorthand(useArrays: true, doubleResetError: true),
          throwsException);
    });
  });

  test('reset and value types', () async {
    final dut = SeqResetValTypes(
      Logic(),
      Logic(width: 8),
    );
    await dut.build();

    final vectors = [
      Vector({'reset': 1, 'i': 17}, {}),
      Vector({'reset': 1}, {'a': 7, 'b': 12, 'c': 17, 'd': 0}),
      Vector({'reset': 0}, {'a': 7, 'b': 12, 'c': 17, 'd': 0}),
      Vector({'reset': 0}, {'a': 8, 'b': 13, 'c': 18, 'd': 4}),
    ];

    await SimCompare.checkFunctionalVector(dut, vectors);
    SimCompare.checkIverilogVector(dut, vectors);
  });

  test('negedge triggered flop', () async {
    final mod = NegedgeTriggeredSeq(Logic());
    await mod.build();

    final sv = mod.generateSynth();
    expect(sv, contains('always_ff @(negedge'));

    final vectors = [
      Vector({'a': 0}, {}),
      Vector({'a': 1}, {'b': 0}),
      Vector({'a': 0}, {'b': 1}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('multiple triggers, both edges', () async {
    final mod = BothTriggeredSeq(Logic());
    await mod.build();

    final vectors = [
      Vector({'reset': 1}, {}),
      Vector({'reset': 1}, {'b': 0}),
      Vector({'reset': 0}, {'b': 0}),
      Vector({}, {'b': 2}),
      Vector({}, {'b': 4}),
      Vector({}, {'b': 6}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('negedge trigger actually occurs on negedge', () async {
    final clk = Logic()..put(0);

    final a = Logic()..put(1);
    final b = Logic();

    Sequential.multi([], negedgeTriggers: [clk], [b < a]);

    Simulator.registerAction(20, () => clk.put(1));

    Simulator.registerAction(30, () => expect(b.value, LogicValue.z));

    Simulator.registerAction(40, () => clk.put(0));

    Simulator.registerAction(50, () => expect(b.value, LogicValue.one));

    await Simulator.run();
  });

  test('invalid trigger after valid trigger still causes x prop', () async {
    final c1 = Logic()..put(0);
    final c2 = Logic()..put(LogicValue.x);

    final a = Logic()..put(1);
    final b = Logic();

    Sequential.multi([c1, c2], [b < a]);

    Simulator.registerAction(20, () => c1.put(1));

    Simulator.registerAction(30, () => expect(b.value, LogicValue.x));

    await Simulator.run();
  });
}
