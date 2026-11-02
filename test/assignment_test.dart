// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// assignment_test.dart
// Unit tests for assignment-specific issues.
//
// 2022 September 19
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ExampleModule extends Module {
  ExampleModule() {
    final out = addOutput('out');
    final val = Logic(name: 'val');
    val <= Const(1);

    Combinational([out < val]);
  }

  Logic get out => output('out');
}

class LogicSubsetModule extends Module {
  LogicSubsetModule(int offset, int resultWidth, Logic subset) {
    subset = addInput('subset', subset, width: subset.width);

    addOutput('result', width: resultWidth)
        .assignSubset(subset.elements, start: offset);
  }
}

class MyStruct extends LogicStructure {
  final Logic smaller;
  final Logic big;

  factory MyStruct({String name = 'myStruct'}) => MyStruct._(
        Logic(name: 'smaller'),
        Logic(name: 'big', width: 8),
        name: name,
      );

  MyStruct._(this.smaller, this.big, {required String name})
      : super([smaller, big], name: name);

  @override
  MyStruct clone({String? name}) => MyStruct(name: name ?? this.name);
}

class LogicStructSubsetModule extends Module {
  LogicStructSubsetModule(Logic smaller, Logic big) {
    smaller = addInput('smaller', smaller);
    big = addInput('big', big, width: 8);

    final struct = MyStruct()..assignSubset([smaller, big]);

    addOutput('result', width: struct.width) <= struct;
  }
}

class LogicNetSubsetModule extends Module {
  LogicNetSubsetModule(int offset1, int offset2, LogicNet subset1,
      LogicNet subset2, LogicNet result) {
    subset1 = addInOut('subset1', subset1, width: subset1.width);
    subset2 = addInOut('subset2', subset2, width: subset2.width);

    result = addInOut('result', result, width: result.width)
      ..assignSubset(subset1.elements, start: offset1)
      ..assignSubset(subset2.elements, start: offset2);
  }
}

class _SwizzleReceiverModule extends Module {
  _SwizzleReceiverModule(Logic source) {
    source = addInput('source', source, width: source.width);
    final upper = addOutput('upper', width: 4);
    final lower = addOutput('lower', width: 4);

    [upper, lower].swizzle() <= source;
  }
}

class _SubsetReceiverModule extends Module {
  _SubsetReceiverModule(Logic source) {
    source = addInput('source', source, width: source.width);
    final destination = addOutput('destination', width: 8);

    destination.slice(5, 3) <= source;
  }
}

class _NetSwizzleReceiverModule extends Module {
  _NetSwizzleReceiverModule(
    LogicNet source,
    LogicNet targetUpper,
    LogicNet targetLower,
  ) {
    source = addInOut('source', source, width: 8);
    targetUpper = addInOut('targetUpper', targetUpper, width: 4);
    targetLower = addInOut('targetLower', targetLower, width: 4);

    [targetUpper, targetLower].swizzle() <= source;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  // From https://github.com/intel/rohd/issues/159
  // Thank you to @chykon for reporting!
  test('const comb assignment', () async {
    final exampleModule = ExampleModule();
    await exampleModule.build();

    final vectors = [
      Vector({}, {'out': 1}),
    ];
    await SimCompare.checkVectors(
      exampleModule,
      vectors,
      allowIverilogWarnings: true, // always_comb has no sensitivities
    );
  });

  group('assign subset', () {
    group('logic', () {
      test('single bit', () async {
        final mod = LogicSubsetModule(3, 8, Logic());
        await mod.build();

        final vectors = [
          Vector(
              {'subset': bin('1')}, {'result': LogicValue.ofString('zzzz1zzz')})
        ];

        await SimCompare.checkVectors(
          mod,
          vectors,
          excludedBackends: const {
            SimCompareBackend.systemc:
                'This case checks undriven bits retaining Z values.',
          },
        );
      });

      test('multiple bits', () async {
        final mod = LogicSubsetModule(2, 8, Logic(width: 4));
        await mod.build();

        final vectors = [
          Vector({'subset': bin('0110')},
              {'result': LogicValue.ofString('zz0110zz')})
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });

      test('width mismatch fails', () {
        expect(() => Logic(width: 8).assignSubset([Logic(width: 4)]),
            throwsA(isA<SignalWidthMismatchException>()));
      });

      test('out of bounds fails', () {
        expect(() => Logic(width: 8).assignSubset([Logic(), Logic()], start: 7),
            throwsA(isA<SignalWidthMismatchException>()));
      });
    });

    test('logic structure', () async {
      final mod = LogicStructSubsetModule(Logic(), Logic(width: 8));
      await mod.build();

      final vectors = [
        Vector(
            {'smaller': bin('1'), 'big': bin('1010')}, {'result': bin('10101')})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    group('logic net is multi-assignable', () {
      test('forward', () async {
        final mod = LogicNetSubsetModule(
          2,
          4,
          LogicNet(width: 4),
          LogicNet(width: 4),
          LogicNet(width: 8),
        );
        await mod.build();

        final vectors = [
          Vector({'subset1': bin('0000'), 'subset2': bin('1111')},
              {'result': LogicValue.ofString('11xx00zz')})
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });

      test('reversed', () async {
        final mod = LogicNetSubsetModule(
          2,
          4,
          LogicNet(width: 4),
          LogicNet(width: 4),
          LogicNet(width: 8),
        );
        await mod.build();

        final vectors = [
          Vector({
            'result': LogicValue.ofString('110100xx')
          }, {
            'subset1': LogicValue.ofString('0100'),
            'subset2': LogicValue.ofString('1101')
          })
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    });
  });

  group('receiver views', () {
    test('swizzle receiver routes source ranges to each signal', () async {
      final dut = _SwizzleReceiverModule(Logic(width: 8));
      await dut.build();

      final sv = dut.dumpSystemVerilog();
      expect(sv, contains('assign upper = source[7:4];'));
      expect(sv, contains('assign lower = source[3:0];'));

      final vectors = [
        Vector({'source': 0xa5}, {'upper': 0xa, 'lower': 0x5}),
        Vector({'source': 0x3c}, {'upper': 0x3, 'lower': 0xc}),
      ];

      await SimCompare.checkFunctionalVector(dut, vectors);
      SimCompare.checkIverilogVector(dut, vectors);
    });

    test('subset receiver updates only its selected destination range',
        () async {
      final dut = _SubsetReceiverModule(Logic(width: 3));
      await dut.build();

      final sv = dut.dumpSystemVerilog();
      expect(sv, contains('assign destination'));

      final vectors = [
        Vector(
          {'source': 0x5},
          {'destination': LogicValue.ofString('zz101zzz')},
        ),
        Vector(
          {'source': 0x2},
          {'destination': LogicValue.ofString('zz010zzz')},
        ),
      ];

      await SimCompare.checkFunctionalVector(dut, vectors);
      SimCompare.checkIverilogVector(dut, vectors);
    });

    test('net swizzle receiver generates direct net connections', () async {
      final dut = _NetSwizzleReceiverModule(
        LogicNet(width: 8),
        LogicNet(width: 4),
        LogicNet(width: 4),
      );
      await dut.build();

      final sv = dut.dumpSystemVerilog();
      expect(sv, contains('(targetUpper, (source[7:4]))'));
      expect(sv, contains('(targetLower, (source[3:0]))'));
      expect(sv, isNot(contains('_swizzled')));

      final vectors = [
        Vector(
          {'source': 0xa5},
          {'targetUpper': 0xa, 'targetLower': 0x5},
        ),
        Vector(
          {'source': 0x3c},
          {'targetUpper': 0x3, 'targetLower': 0xc},
        ),
      ];

      await SimCompare.checkFunctionalVector(dut, vectors);
      SimCompare.checkIverilogVector(dut, vectors);
    });

    test('net swizzle retains direct driver behavior', () {
      final upperDriver = Logic(width: 2);
      final lowerDriver = Logic();
      final swizzledDriver = Logic(width: 3);
      final upper = LogicNet(width: 2)..gets(upperDriver);
      final lower = LogicNet()..gets(lowerDriver);
      final swizzled = [upper, lower].swizzle();

      upperDriver.put('10');
      lowerDriver.put('1');
      expect(swizzled.value, LogicValue.of('101'));

      swizzled.gets(swizzledDriver);
      swizzledDriver.put('111');
      expect(upper.value, LogicValue.of('1x'));
    });
  });
}
