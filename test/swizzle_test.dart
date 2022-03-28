/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// swizzle_test.dart
/// Tests for swizzling values
///
/// 2022 January 6
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class SwizzlyModule extends Module {
  SwizzlyModule(Logic a) {
    a = addInput('a', a);
    var b = addOutput('b', width: 3);
    b <= [Const(1), a, Const(1)].swizzle();
  }
}

void main() {
  group('LogicValue', () {
    test('simple swizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .swizzle(),
          equals(LogicValue.ofString('10xz')));
    });
    test('simple rswizzle', () {
      expect(
          [LogicValue.one, LogicValue.zero, LogicValue.x, LogicValue.z]
              .rswizzle(),
          equals(LogicValue.ofString('zx01')));
    });
  });
  group('LogicValue', () {
    test('simple swizzle', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].swizzle(),
          equals(LogicValue.ofString('10xz')));
    });

    test('simple rswizzle', () {
      expect([LogicValue.ofString('10'), LogicValue.ofString('xz')].rswizzle(),
          equals(LogicValue.ofString('xz10')));
    });
  });

  group('Logic', () {
    test('simple swizzle', () async {
      var mod = SwizzlyModule(Logic());
      await mod.build();
      var vectors = [
        Vector({'a': 0}, {'b': bin('101')}),
        Vector({'a': 1}, {'b': bin('111')}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(
          mod.generateSynth(), mod.runtimeType.toString(), vectors,
          signalToWidthMap: {'b': 3});
      expect(simResult, equals(true));
    });
  });
}
