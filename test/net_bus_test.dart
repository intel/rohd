// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// net_bus_test.dart
// Tests for bus operations on LogicNets
//
// 2024 October 4
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SubsetMod extends Module {
  LogicNet get subset => inOut('subset') as LogicNet;

  SubsetMod(LogicNet bus, LogicNet subset, {int start = 1}) {
    bus = addInOut('bus', bus, width: bus.width);
    subset = addInOut('subset', subset, width: subset.width);

    subset <= bus.getRange(start, start + subset.width);
  }
}

class SwizzleMod extends Module {
  LogicNet get swizzled => inOutSource('swizzled') as LogicNet;

  SwizzleMod(List<Logic> toSwizzle) {
    final innerToSwizzle = <Logic>[];
    var i = 0;
    for (final ts in toSwizzle) {
      final name = 'in$i';
      Logic p;
      if (ts is LogicArray) {
        if (ts.isNet) {
          p = addInOutArray(name, ts,
              dimensions: ts.dimensions, elementWidth: ts.elementWidth);
        } else {
          p = addInputArray(name, ts,
              dimensions: ts.dimensions, elementWidth: ts.elementWidth);
        }
      } else {
        if (ts is LogicNet) {
          p = addInOut(name, ts, width: ts.width);
        } else {
          p = addInput(name, ts, width: ts.width);
        }
      }

      innerToSwizzle.add(p);
      i++;
    }

    final swizzled = innerToSwizzle.swizzle();

    addInOut('swizzled', LogicNet(width: swizzled.width),
            width: swizzled.width) <=
        swizzled;
  }
}

class ReverseMod extends Module {
  ReverseMod(LogicNet bus) {
    bus = addInOut('bus', bus, width: bus.width);

    addInOut('reversed', LogicNet(width: bus.width), width: bus.width) <=
        bus.reversed;
  }
}

class IndexMod extends Module {
  IndexMod(LogicNet bus, int index) {
    bus = addInOut('bus', bus, width: bus.width);
    addInOut('indexed', LogicNet()) <= bus[index];
  }
}

class MultiConnectionNetSubsetMod extends Module {
  MultiConnectionNetSubsetMod(LogicNet bus1, LogicNet bus2) {
    bus1 = addInOut('bus1', bus1, width: 8);
    bus2 = addInOut('bus2', bus2, width: 8);

    bus1.getRange(0, 4) <= bus2.getRange(4, 8);
    bus2.getRange(0, 4) <= [bus1.getRange(0, 2), bus1.getRange(6, 8)].swizzle();

    bus1.getRange(4, 8) <= bus2.getRange(4, 8).reversed;

    // bus1: 0011 1100
    // bus2: 1100 0000
  }
}

//TODO: test combinational loops are properly caught!

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  //TODO: testplan
  // - swizzle
  //    - just nets
  //    - nets and normals
  //    - array nets
  //    - array nets and array normals
  // - subset
  //    - on net
  //    - on array net
  // - collapsing of assignments in generated SV
  // - multiple connections!
  // - all kinds of shifts (signed arithmetic shift especially!)
  // - zero and sign extensions
  // - reversed

  group('multi-connection', () {
    group('func only', () {
      test('tied subsets', () async {
        final base = LogicNet(width: 8);

        final lowerDriver = Logic(width: 4);
        final upperDriver = Logic(width: 4);
        final midDriver = Logic(width: 4);

        final lower = base.getRange(0, 4)..gets(lowerDriver);
        final upper = base.getRange(4, 8)..gets(upperDriver);
        final mid = base.getRange(2, 6)..gets(midDriver);

        upper <= mid;

        lowerDriver.put('1100');

        expect(lower.value, LogicValue.of('1100'));
        expect(mid.value, LogicValue.of('1111'));
        expect(upper.value, LogicValue.of('1111'));

        upperDriver.put('0000');

        expect(upper.value, LogicValue.of('xxxx'));
        expect(mid.value, LogicValue.of('xxxx'));
        expect(lower.value, LogicValue.of('xx00'));

        lowerDriver.put('zzzz');

        expect(upper.value, LogicValue.of('0000'));
        expect(mid.value, LogicValue.of('0000'));
        expect(lower.value, LogicValue.of('00zz'));
      });

      test('multiple getRange connections', () {
        final baseDriver = Logic(width: 8);
        final base = LogicNet(width: 8)..gets(baseDriver);

        base.getRange(0, 2) <= base.getRange(2, 4);
        base.getRange(0, 2) <= base.getRange(4, 6);
        base.getRange(2, 4) <= base.getRange(6, 8);

        baseDriver.put('zzzzzz01');

        expect(base.value, LogicValue.of('01' * 4));
      });
    });

    test('driving bus1', () async {
      final mod =
          MultiConnectionNetSubsetMod(LogicNet(width: 8), LogicNet(width: 8));

      await mod.build();

      print(mod.generateSynth());

      final vectors = [
        Vector({'bus1': 'zzzz1100'}, {'bus2': '11000000'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('index', () {
    test('func sim', () {
      final busDriver = Logic(width: 8);
      final indexedDriver = Logic();

      final bus = LogicNet(width: 8)..gets(busDriver);
      final indexed = LogicNet()..gets(indexedDriver);
      indexed <= bus[3];

      busDriver.put('00001000');

      expect(indexed.value, LogicValue.one);
      expect(bus.value, LogicValue.of('00001000'));

      indexedDriver.put('0');

      expect(indexed.value, LogicValue.x);
      expect(bus.value, LogicValue.of('0000x000'));

      busDriver.put(LogicValue.z);

      expect(indexed.value, LogicValue.zero);
      expect(bus.value, LogicValue.of('zzzz0zzz'));
    });

    test('drive bus', () async {
      final bus = LogicNet(width: 8);
      final mod = IndexMod(bus, 3);

      await mod.build();

      final sv = mod.generateSynth();
      expect(
          sv,
          contains(
              'net_connect #(.WIDTH(1)) net_connect (indexed, (bus[3]));'));

      final vectors = [
        Vector({'bus': '00101100'}, {'indexed': '1'}),
        Vector({'bus': '00100100'}, {'indexed': '0'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('drive index', () async {
      final bus = LogicNet(width: 8);
      final mod = IndexMod(bus, 3);

      await mod.build();

      final vectors = [
        Vector({'indexed': '1'}, {'bus': 'zzzz1zzz'}),
        Vector({'indexed': '0'}, {'bus': 'zzzz0zzz'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('reversed', () {
    test('func sim', () {
      final busDriver = Logic(name: 'busDriver', width: 8);
      final reversedDriver = Logic(name: 'reversedDriver', width: 8);

      final bus = LogicNet(name: 'myBus', width: 8)..gets(busDriver);
      final reversed = LogicNet(name: 'myReversed', width: 8)
        ..gets(reversedDriver);
      reversed <= bus.reversed;

      busDriver.put('00101100');

      expect(reversed.value, LogicValue.of('00110100'));

      reversedDriver.put('11001100');

      expect(bus.value, LogicValue.of('001xxxxx'));
      expect(reversed.value, LogicValue.of('xxxxx100'));

      busDriver.put(LogicValue.z);

      expect(reversed.value, LogicValue.of('11001100'));
      expect(bus.value, LogicValue.of('00110011'));
    });

    test('drive bus', () async {
      final bus = LogicNet(width: 8);
      final mod = ReverseMod(bus);

      await mod.build();

      final sv = mod.generateSynth();
      expect(
          sv,
          contains(
              'net_connect #(.WIDTH(8)) net_connect (reversed, (bus[7:0]));'));

      final vectors = [
        Vector({'bus': '00101100'}, {'reversed': '00110100'}),
        Vector({'bus': '11001100'}, {'reversed': '11001100'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  group('subset', () {
    group('on net', () {
      test('func sim', () {
        final busDriver = Logic(width: 8);
        final subsetDriver = Logic(width: 4);

        final bus = LogicNet(width: 8)..gets(busDriver);
        final subset = LogicNet(width: 4)..gets(subsetDriver);
        subset <= BusSubset(bus, 2, 5).subset;

        busDriver.put('00101100');

        expect(subset.value, LogicValue.of('1011'));

        subsetDriver.put('1100');

        expect(bus.value, LogicValue.of('001xxx00'));
        expect(subset.value, LogicValue.of('1xxx'));

        busDriver.put(LogicValue.z);

        expect(subset.value, LogicValue.of('1100'));
        expect(bus.value, LogicValue.of('zz1100zz'));
      });

      test('bus to subset', () async {
        final bus = LogicNet(width: 8);
        final subset = LogicNet(width: 4);
        final mod = SubsetMod(bus, subset, start: 2);

        await mod.build();

        final sv = mod.generateSynth();
        expect(
            sv,
            contains(
                'net_connect #(.WIDTH(4)) net_connect (subset, (bus[5:2]));'));

        final vectors = [
          Vector({'bus': '10000101'}, {'subset': '0001'}),
          Vector({'bus': 'xx1100xx'}, {'subset': '1100'}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });

      test('subset to bus', () async {
        final bus = LogicNet(width: 8);
        final subset = LogicNet(width: 4);
        final mod = SubsetMod(bus, subset, start: 2);

        await mod.build();

        final sv = mod.generateSynth();
        expect(
            sv,
            contains(
                'net_connect #(.WIDTH(4)) net_connect (subset, (bus[5:2]));'));

        final vectors = [
          Vector({'subset': '0001'}, {'bus': 'zz0001zz'}),
          Vector({'subset': '1100'}, {'bus': 'zz1100zz'}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    });
  });

  group('swizzle', () {
    group('just nets', () {
      test('func sim', () {
        final upperDriver = Logic(width: 2);
        final lowerDriver = Logic();
        final swizzeldDriver = Logic(width: 3);

        final upper = LogicNet(width: 2, name: 'upper')..gets(upperDriver);
        final lower = LogicNet(name: 'lower')..gets(lowerDriver);
        final swizzled = [
          upper,
          lower,
        ].swizzle()
          ..gets(swizzeldDriver);

        upperDriver.put('10');

        expect(swizzled.value, LogicValue.of('10z'));
        expect(lower.value, LogicValue.of('z'));
        expect(upper.value, LogicValue.of('10'));

        lowerDriver.put('1');

        expect(swizzled.value, LogicValue.of('101'));
        expect(lower.value, LogicValue.of('1'));
        expect(upper.value, LogicValue.of('10'));

        swizzeldDriver.put('111');

        expect(swizzled.value, LogicValue.of('1x1'));
        expect(lower.value, LogicValue.of('1'));
        expect(upper.value, LogicValue.of('1x'));

        upperDriver.put('zz');

        expect(swizzled.value, LogicValue.of('111'));
        expect(lower.value, LogicValue.of('1'));
        expect(upper.value, LogicValue.of('11'));
      });

      test('many to one', () async {
        final mod = SwizzleMod([
          LogicNet(width: 8), // in0
          LogicNet(width: 4), // in1
          LogicNet(width: 4), // in2
        ]);

        await mod.build();

        final sv = mod.generateSynth();
        expect(
            sv,
            contains('net_connect #(.WIDTH(16))'
                ' net_connect (swizzled, ({in0,in1,in2}));'));

        final vectors = [
          Vector({'in0': 0xab, 'in1': 0xc, 'in2': 0xd}, {'swizzled': 0xabcd}),
          Vector({'in0': 0x12, 'in1': 0x3, 'in2': 0x4}, {'swizzled': 0x1234}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });

      test('one to many', () async {
        final mod = SwizzleMod([
          LogicNet(width: 8), // in0
          LogicNet(width: 4), // in1
          LogicNet(width: 4), // in2
        ]);

        await mod.build();

        final sv = mod.generateSynth();
        expect(
            sv,
            contains('net_connect #(.WIDTH(16))'
                ' net_connect (swizzled, ({in0,in1,in2}));'));

        final vectors = [
          Vector({'swizzled': 0xabcd}, {'in0': 0xab, 'in1': 0xc, 'in2': 0xd}),
          Vector({'swizzled': 0x1234}, {'in0': 0x12, 'in1': 0x3, 'in2': 0x4}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    });
  });
}