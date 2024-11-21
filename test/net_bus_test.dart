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

  SubsetMod(Logic bus, Logic subset, {int start = 1}) {
    bus = bus is LogicArray
        ? addInOutArray('bus', bus,
            dimensions: bus.dimensions, elementWidth: bus.elementWidth)
        : addInOut('bus', bus, width: bus.width);

    subset = subset is LogicArray
        ? addInOutArray('subset', subset,
            dimensions: subset.dimensions, elementWidth: subset.elementWidth)
        : addInOut('subset', subset, width: subset.width);

    subset <= bus.getRange(start, start + subset.width);
  }
}

class SwizzleMod extends Module {
  SwizzleMod(List<Logic> toSwizzle, {bool swapAssign = false}) {
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

    if (!swapAssign || !swizzled.isNet) {
      addInOut('swizzled', LogicNet(width: swizzled.width),
              width: swizzled.width) <=
          swizzled;
    } else {
      swizzled <=
          addInOut('swizzled', LogicNet(width: swizzled.width),
              width: swizzled.width);
    }
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
  }
}

class SimpleNetPassthrough extends Module {
  SimpleNetPassthrough(LogicNet bus1, LogicNet bus2) {
    bus1 = addInOut('bus1', bus1, width: bus1.width);
    bus2 = addInOut('bus2', bus2, width: bus2.width);
    bus1 <= bus2;
  }
}

class DoubleNetPassthrough extends Module {
  DoubleNetPassthrough(LogicNet bus1, LogicNet bus2) {
    bus1 = addInOut('upbus1', bus1, width: bus1.width);
    bus2 = addInOut('upbus2', bus2, width: bus2.width);
    final busIntermediate = LogicNet(name: 'intermediate', width: bus1.width);
    SimpleNetPassthrough(bus1, busIntermediate);
    SimpleNetPassthrough(bus2, busIntermediate);
  }
}

class ReplicateMod extends Module {
  ReplicateMod(LogicNet bus, int times) {
    bus = addInOut('bus', bus, width: bus.width);
    addInOut('replicated', LogicNet(width: bus.width * times),
            width: bus.width * times) <=
        bus.replicate(times);
  }
}

class ShiftTestNetModule extends Module {
  dynamic constant; // int or BigInt

  ShiftTestNetModule(LogicNet a, LogicNet b,
      {this.constant = 3, bool inclSra = true})
      : super(name: 'shifttestmodule') {
    a = addInOut('a', a, width: a.width);
    b = addInOut('b', b, width: b.width);

    final aRshiftB =
        addInOut('a_rshift_b', LogicNet(width: a.width), width: a.width);
    final aLshiftB =
        addInOut('a_lshift_b', LogicNet(width: a.width), width: a.width);
    final aArshiftB =
        addInOut('a_arshift_b', LogicNet(width: a.width), width: a.width);

    final aRshiftConst =
        addInOut('a_rshift_const', LogicNet(width: a.width), width: a.width);
    final aLshiftConst =
        addInOut('a_lshift_const', LogicNet(width: a.width), width: a.width);
    final aArshiftConst =
        addInOut('a_arshift_const', LogicNet(width: a.width), width: a.width);

    aRshiftB <= a >>> b;
    aLshiftB <= a << b;
    aArshiftB <= a >> b;
    aRshiftConst <= a >>> constant;
    aLshiftConst <= a << constant;
    if (inclSra) {
      aArshiftConst <= a >> constant;
    }
  }
}

//TODO: test combinational loops are properly caught!

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  //TODO: testplan
  // - multiple connections!
  // - all kinds of shifts (signed arithmetic shift especially!)
  // - putting on a LogicNet and it propogates throughout (rather than
  //   immediately go back to driver calc)
  // - sv gen when swizzle assign to swizzle is one assign

  group('simple', () {
    test('double passthrough', () async {
      final dut = DoubleNetPassthrough(LogicNet(width: 8), LogicNet(width: 8));
      await dut.build();

      final sv = dut.generateSynth();

      expect(
          sv,
          contains('SimpleNetPassthrough'
              '  unnamed_module(.bus1(upbus1),.bus2(intermediate));'));
    });

    test('subset glitching', () {
      final netDriver = Logic(width: 8)..put(0);
      final net = LogicNet(name: 'net', width: 8);
      net <= netDriver;

      final subset = net.getRange(0, 4);
      final logic = Logic(width: 4);
      logic <= subset;

      expect(logic.value.toInt(), 0);

      netDriver.put(0x55);

      expect(logic.value.toInt(), 5);
    });
  });

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

      test('chained slices', () {
        final baseDriver = Logic(width: 8);
        final base = LogicNet(width: 8)..gets(baseDriver);

        final slice1 = LogicNet(width: 4)..gets(base.getRange(0, 4));
        final slice2 = LogicNet(width: 2);
        final slice3 = LogicNet();

        slice3 <= slice2.getRange(0, 1);
        slice2 <= slice1.getRange(0, 2);
        final mid = LogicNet(width: 4);
        slice1 <= mid;
        mid <= base.getRange(0, 4);

        baseDriver.put('11111111');

        expect(slice3.value, LogicValue.of('1'));

        baseDriver.put('zzzzzzz0');
        expect(slice3.value, LogicValue.of('0'));
      });
    });

    test('driving bus1', () async {
      final mod =
          MultiConnectionNetSubsetMod(LogicNet(width: 8), LogicNet(width: 8));

      await mod.build();

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
          contains('net_connect (reversed, '
              '({bus[0],bus[1],bus[2],bus[3],bus[4],bus[5],bus[6],bus[7]}));'));

      final vectors = [
        Vector({'bus': '00101100'}, {'reversed': '00110100'}),
        Vector({'bus': '11001100'}, {'reversed': '00110011'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('drive reversed', () async {
      final reversed = LogicNet(width: 8);
      final mod = ReverseMod(reversed);

      await mod.build();

      final vectors = [
        Vector({'reversed': '00110100'}, {'bus': '00101100'}),
        Vector({'reversed': '00110011'}, {'bus': '11001100'}),
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

      group('simcompare', () {
        final netTypes = {
          LogicNet: () => (LogicNet(width: 8), LogicNet(width: 4)),
          LogicArray: () => (LogicArray.net([2, 4], 1), LogicArray.net([2], 2)),
        };

        for (final MapEntry(key: netTypeName, value: sigGen)
            in netTypes.entries) {
          group(netTypeName, () {
            test('bus to subset', () async {
              final (bus, subset) = sigGen();
              final mod = SubsetMod(bus, subset, start: 2);

              await mod.build();

              final sv = mod.generateSynth();
              if (netTypeName == LogicNet) {
                expect(
                    sv,
                    contains('net_connect'
                        ' #(.WIDTH(4)) net_connect (subset, (bus[5:2]));'));
              } else if (netTypeName == LogicArray) {
                expect(
                    sv,
                    contains('net_connect_0'
                        ' (_original__swizzled, '
                        '({bus[1][1],bus[1][0],bus[0][3],bus[0][2]}));'));
              }

              final vectors = [
                Vector({'bus': '10000101'}, {'subset': '0001'}),
                Vector({'bus': 'xx1100xx'}, {'subset': '1100'}),
              ];

              await SimCompare.checkFunctionalVector(mod, vectors);
              SimCompare.checkIverilogVector(mod, vectors);
            });

            test('subset to bus', () async {
              final (bus, subset) = sigGen();
              final mod = SubsetMod(bus, subset, start: 2);

              await mod.build();

              final sv = mod.generateSynth();
              if (netTypeName == LogicNet) {
                expect(
                    sv,
                    contains('net_connect'
                        ' #(.WIDTH(4)) net_connect (subset, (bus[5:2]));'));
              } else if (netTypeName == LogicArray) {
                expect(
                    sv,
                    contains('net_connect_0'
                        ' (_original__swizzled, '
                        '({bus[1][1],bus[1][0],bus[0][3],bus[0][2]}));'));
              }

              final vectors = [
                Vector({'subset': '0001'}, {'bus': 'zz0001zz'}),
                Vector({'subset': '1100'}, {'bus': 'zz1100zz'}),
              ];

              await SimCompare.checkFunctionalVector(mod, vectors);
              SimCompare.checkIverilogVector(mod, vectors);
            });
          });
        }
      });
    });
  });

  group('swizzle', () {
    test('func mixed net and non-net', () {
      final myNetDriver = Logic(name: 'my_net_driver');
      final myNet = LogicNet(name: 'my_net')..gets(myNetDriver);
      final myNonNet = Logic(name: 'my_non_net');
      final swizzledDriver = Logic(name: 'swizzled_driver', width: 2);
      final swizzled = [
        myNet,
        myNonNet,
      ].swizzle()
        ..gets(swizzledDriver);

      myNetDriver.put(1);
      myNonNet.put(0);

      expect(swizzled.value, LogicValue.of('10'));

      myNet.glitch.listen((_) {
        print('asdf');
      });

      swizzledDriver.put('01');

      expect(swizzled.value, LogicValue.of('xx'));
      expect(myNet.value, LogicValue.of('x'));
    });

    test('func swizzle to swizzle nets', () {
      final a0Driver = Logic();

      final a0 = LogicNet()..gets(a0Driver);
      final a1 = LogicNet();
      final a = [a0, a1].rswizzle();

      final inner = LogicNet(width: 2);

      final b0 = LogicNet();
      final b1 = LogicNet();
      final b = [b0, b1].rswizzle();

      inner <= a;
      b <= inner;

      a0Driver.put(1);

      expect(b0.value, LogicValue.of('1'));

      a0Driver.put(0);

      expect(b0.value, LogicValue.of('0'));
    });

    for (final swapAssign in [false, true]) {
      SwizzleMod swizzleModConstructor(List<Logic> toSwizzle) =>
          SwizzleMod(toSwizzle, swapAssign: swapAssign);

      group('swap=$swapAssign', () {
        group('build checks', () {
          test('simple net array', () async {
            final mod = swizzleModConstructor([
              LogicArray.net([1], 8),
              LogicArray.net([1], 8),
            ]);

            await mod.build();

            final sv = mod.generateSynth();

            expect(sv, contains('net_connect (swizzled, ({in0[0],in1[0]}));'));
          });

          test('simple net array multi dim with simple net', () async {
            final mod = swizzleModConstructor([
              LogicNet(),
              LogicArray.net([2], 2),
            ]);

            await mod.build();

            final sv = mod.generateSynth();

            expect(
                sv,
                contains('net_connect #(.WIDTH(5)) net_connect'
                    ' (swizzled, ({in0,({in1[1],in1[0]})}));'));
          });

          test('non-net array', () async {
            final mod = swizzleModConstructor([
              LogicArray([2, 2], 2), // in0
              LogicArray([4], 1), // in1
            ]);

            await mod.build();

            final sv = mod.generateSynth();

            expect(
                sv,
                contains('assign _swizzled = '
                    '{({({in0[1][1],in0[1][0]}),({in0[0][1],in0[0][0]})}),'
                    '({in1[3],in1[2],in1[1],in1[0]})};'));
          });

          test('net array 2', () async {
            final mod = swizzleModConstructor([
              LogicArray.net([4], 1), // in0
              LogicArray.net([1], 4), // in1
            ]);

            await mod.build();

            final sv = mod.generateSynth();

            expect(
                sv,
                contains('net_connect (swizzled,'
                    ' ({({in0[3],in0[2],in0[1],in0[0]}),in1[0]}));'));
          });

          test('net array 3', () async {
            final mod = swizzleModConstructor([
              LogicArray.net([2, 2], 2), // in0
              LogicArray.net([4], 1), // in1
              LogicArray.net([1], 4), // in2
            ]);

            await mod.build();

            final sv = mod.generateSynth();

            expect(
                sv,
                contains('net_connect (swizzled, '
                    '({({({in0[1][1],in0[1][0]}),'
                    '({in0[0][1],in0[0][0]})}),'
                    '({in1[3],in1[2],in1[1],in1[0]}),in2[0]}));'));
          });

          test('net and non-net', () async {
            final mod = swizzleModConstructor([
              Logic(width: 2),
              LogicNet(width: 4),
            ]);

            await mod.build();
            final sv = mod.generateSynth();

            expect(sv, contains('assign _in1 = in0;'));
            expect(
                sv,
                contains('net_connect #(.WIDTH(6)) net_connect'
                    ' (swizzled, ({_in1,in1}));'));
          });

          test('net and non-net arrays', () async {
            final mod = swizzleModConstructor([
              LogicArray.net([2], 2),
              LogicArray([3], 4),
            ]);

            await mod.build();
            final sv = mod.generateSynth();

            expect(
                sv,
                contains('net_connect #(.WIDTH(16)) net_connect'
                    ' (swizzled, ({({in0[1],in0[0]}),_in0}));'));
          });
        });

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

          group('simcompare', () {
            group('types', () {
              final netTypes = {
                LogicNet: () => [
                      LogicNet(width: 8), // in0
                      LogicNet(width: 4), // in1
                      LogicNet(width: 4), // in2
                    ],
                LogicArray: () => [
                      LogicArray.net([2, 2], 2), // in0
                      LogicArray.net([4], 1), // in1
                      LogicArray.net([1], 4), // in2
                    ],
              };

              for (final MapEntry(key: netTypeName, value: sigGen)
                  in netTypes.entries) {
                void checkSV(String sv) {
                  if (netTypeName == LogicNet) {
                    expect(
                        sv,
                        contains('net_connect #(.WIDTH(16))'
                            ' net_connect (swizzled, ({in0,in1,in2}));'));
                  } else if (netTypeName == LogicArray) {
                    expect(
                        sv,
                        contains(
                            'net_connect #(.WIDTH(16)) net_connect (swizzled, '
                            '({({({in0[1][1],in0[1][0]}),'
                            '({in0[0][1],in0[0][0]})}),'
                            '({in1[3],in1[2],in1[1],in1[0]}),in2[0]}));'));
                  }
                }

                group(netTypeName, () {
                  test('many to one', () async {
                    final mod = swizzleModConstructor(sigGen());

                    await mod.build();

                    final sv = mod.generateSynth();
                    checkSV(sv);

                    final vectors = [
                      Vector({'in0': 0xab, 'in1': 0xc, 'in2': 0xd},
                          {'swizzled': 0xabcd}),
                      Vector({'in0': 0x12, 'in1': 0x3, 'in2': 0x4},
                          {'swizzled': 0x1234}),
                    ];

                    await SimCompare.checkFunctionalVector(mod, vectors);
                    SimCompare.checkIverilogVector(mod, vectors);
                  });

                  test('one to many', () async {
                    final mod = swizzleModConstructor(sigGen());

                    await mod.build();

                    final sv = mod.generateSynth();
                    checkSV(sv);

                    final vectors = [
                      Vector({'swizzled': 0xabcd},
                          {'in0': 0xab, 'in1': 0xc, 'in2': 0xd}),
                      Vector({'swizzled': 0x1234},
                          {'in0': 0x12, 'in1': 0x3, 'in2': 0x4}),
                    ];

                    await SimCompare.checkFunctionalVector(mod, vectors);
                    SimCompare.checkIverilogVector(mod, vectors);
                  });
                });
              }
            });

            test('mixed everything many to one', () async {
              final mod = swizzleModConstructor([
                Logic(width: 4),
                LogicNet(width: 4),
                LogicArray([2], 2),
                LogicArray.net([2], 2),
              ]);
              await mod.build();

              final vectors = [
                Vector({'in0': 0xa, 'in1': 0xb, 'in2': 0xc, 'in3': 0xd},
                    {'swizzled': 0xabcd}),
                Vector({'in0': 0x1, 'in1': 0x2, 'in2': 0x3, 'in3': 0x4},
                    {'swizzled': 0x1234}),
              ];

              await SimCompare.checkFunctionalVector(mod, vectors);
              SimCompare.checkIverilogVector(mod, vectors);
            });

            test('mixed everything one to many', () async {
              final mod = swizzleModConstructor([
                Logic(width: 4),
                LogicNet(width: 4),
                LogicArray([2], 2),
                LogicArray.net([2], 2),
              ]);
              await mod.build();

              final vectors = [
                Vector({'swizzled': 0xabcd}, {'in1': 0xb, 'in3': 0xd}),
                Vector({'swizzled': 0x1234}, {'in1': 0x2, 'in3': 0x4}),
              ];

              await SimCompare.checkFunctionalVector(mod, vectors);
              SimCompare.checkIverilogVector(mod, vectors);
            });
          });
        });
      });
    }
  });

  group('shift', () {
    group('func sim', () {
      test('right logical', () {
        //TODO: figure out what's wrong with this!!
        //  it looks like some glitch listner is not getting updated?

        final aDriver = Logic(width: 8, name: 'aDriver');
        final aRshiftBDriver = Logic(width: 8, name: 'aRshiftBDriver');

        final a = LogicNet(width: 8)..gets(aDriver);

        final aRshiftB = LogicNet(width: 8, name: 'aRshiftB')
          ..gets(aRshiftBDriver)
          ..gets(a >>> 3);

        aDriver.put('00101100');

        expect(aRshiftB.value, LogicValue.of('00000101'));

        aRshiftBDriver.put('11110000');

        expect(aRshiftB.value, LogicValue.of('xxxx0x0x'));
        expect(a.value, LogicValue.of('x0x0x100'));

        print('=================');
        aDriver.put('zzzzzzzz');

        expect(a.value, LogicValue.of('10000zzz'));

        //TODO bug! there should be contention here on upper bits since not 0
        expect(aRshiftB.value, LogicValue.of('xxx10000'));
      });
    });
  });

  group('replicate', () {
    test('func sim', () {
      final busDriver = Logic(width: 8);
      final replicatedDriver = Logic(width: 16);

      final bus = LogicNet(width: 8)..gets(busDriver);
      final replicated = LogicNet(width: 16)..gets(replicatedDriver);
      replicated <= bus.replicate(2);

      busDriver.put('00101100');

      expect(replicated.value, LogicValue.of('0010110000101100'));

      busDriver.put(0xab);

      expect(replicated.value.toInt(), 0xabab);

      busDriver.put(LogicValue.z);

      replicatedDriver.put('1111000010101010');

      expect(bus.value, LogicValue.of('1x1xx0x0'));

      busDriver.put('0zzzzzz1');

      expect(bus.value, LogicValue.of('xx1xx0xx'));
    });

    test('simcompare one to many', () async {
      final mod = ReplicateMod(LogicNet(width: 4), 2);
      await mod.build();

      final sv = mod.generateSynth();

      expect(
          sv,
          contains('net_connect #(.WIDTH(8)) net_connect '
              '(replicated, ({2{bus}}));'));

      final vectors = [
        Vector({'bus': '0011'}, {'replicated': '00110011'}),
        Vector({'bus': '1100'}, {'replicated': '11001100'}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);

      // disabled pending feature support in icarus verilog
      //  (https://github.com/steveicarus/iverilog/issues/1178)
      // SimCompare.checkIverilogVector(mod, vectors);
    });
  });
}
