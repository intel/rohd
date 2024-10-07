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

//TODO: test combinational loops are properly caught!

void main() {
  //TODO: testplan
  // - swizzle
  //    - just nets
  //    - nets and normals
  //    - array nets
  //    - array nets and array normals
  // - subset
  //    - on net
  //    - on array net

  group('subset', () {
    group('on net', () {
      test('bus to subset', () async {
        final bus = LogicNet(width: 8);
        final subset = LogicNet(width: 4);
        final mod = SubsetMod(bus, subset, start: 2);

        await mod.build();

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

        print(mod.generateSynth());

        final vectors = [
          Vector({'subset': '0001'}, {'bus': 'zz0001zz'}),
          Vector({'subset': '1100'}, {'bus': 'zz1100zz'}),
        ];

        // await SimCompare.checkFunctionalVector(mod, vectors);
        // SimCompare.checkIverilogVector(mod, vectors);
      });
    });
  });

  group('swizzle', () {
    group('just nets', () {
      test('many to one', () async {
        final mod = SwizzleMod([
          LogicNet(width: 8), // in0
          LogicNet(width: 4), // in1
          LogicNet(width: 4), // in2
        ]);

        await mod.build();

        final sv = mod.generateSynth();
        expect(sv, contains('assign swizzled = {in0,in1,in2};'));

        final vectors = [
          Vector({'in0': 0xab, 'in1': 0xc, 'in2': 0xd}, {'swizzled': 0xabcd}),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });

      test('one to many', () {});
    });
  });
}
