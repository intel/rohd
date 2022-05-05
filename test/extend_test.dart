/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// extend_test.dart
/// Unit tests for extend and withSet operations
///
/// 2022 May 4
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum ExtendType { zero, sign }

class ExtendModule extends Module {
  ExtendModule(Logic a, int newWidth, ExtendType extendType) {
    a = addInput('a', a, width: a.width);
    var b = addOutput('b', width: newWidth);

    b <=
        (extendType == ExtendType.zero
            ? a.zeroExtend(newWidth)
            : a.signExtend(newWidth));
  }
}

class WithSetModule extends Module {
  WithSetModule(Logic a, int startIndex, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    var c = addOutput('c', width: a.width);

    c <= a.withSet(startIndex, b);
  }
}

void main() {
  group('Logic', () {
    tearDown(() {
      Simulator.reset();
    });
    group('extend', () {
      Future<void> extendVectors(
          List<Vector> vectors, int newWidth, ExtendType extendType) async {
        var mod = ExtendModule(Logic(width: 8), newWidth, extendType);
        await mod.build();
        await SimCompare.checkFunctionalVector(mod, vectors);
        var simResult = SimCompare.iverilogVector(
            mod.generateSynth(), mod.runtimeType.toString(), vectors,
            signalToWidthMap: {'a': 8, 'b': newWidth});
        expect(simResult, equals(true));
      }

      test('zero extend with same width returns same thing', () async {
        await extendVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xff}, {'b': 0xff}),
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 8, ExtendType.zero);
      });
      test('zero extend with less width throws exception', () {
        expect(() => extendVectors([], 6, ExtendType.zero), throwsException);
      });
      test('sign extend with same width returns same thing', () async {
        await extendVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xff}, {'b': 0xff}),
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 8, ExtendType.sign);
      });
      test('sign extend with less width throws exception', () {
        expect(() => extendVectors([], 6, ExtendType.sign), throwsException);
      });
      test('zero extend pads 0s', () async {
        await extendVectors([
          Vector({'a': 0xff}, {'b': 0xff}),
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 12, ExtendType.zero);
      });
      test('sign extend for positive number pads 0s', () async {
        await extendVectors([
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 12, ExtendType.sign);
      });
      test('sign extend for negative number pads 1s', () async {
        await extendVectors([
          Vector({'a': 0xff}, {'b': 0xfff}),
        ], 12, ExtendType.sign);
      });
    });

    group('withSet', () {
      Future<void> withSetVectors(
          List<Vector> vectors, int startIndex, int updateWidth) async {
        var mod = WithSetModule(
            Logic(width: 8), startIndex, Logic(width: updateWidth));
        await mod.build();
        await SimCompare.checkFunctionalVector(mod, vectors);
        var simResult = SimCompare.iverilogVector(
            mod.generateSynth(), mod.runtimeType.toString(), vectors,
            signalToWidthMap: {'a': 8, 'b': updateWidth, 'c': 8});
        expect(simResult, equals(true));
      }

      test('setting with bigger number throws exception', () {
        expect(() => withSetVectors([], 0, 9), throwsException);
      });
      test('setting with number in middle overrun throws exception', () {
        expect(() => withSetVectors([], 4, 5), throwsException);
      });
      test('setting same width returns only new', () async {
        await withSetVectors([
          Vector({'a': 0x23, 'b': 0xff}, {'c': 0xff}),
          Vector({'a': 0x45, 'b': 0x5a}, {'c': 0x5a}),
        ], 0, 8);
      });
      test('setting at front', () async {
        await withSetVectors([
          Vector({'a': 0x23, 'b': 0xf}, {'c': 0x2f}),
          Vector({'a': 0x4a, 'b': 0x5}, {'c': 0x45}),
        ], 0, 4);
      });
      test('setting at end', () async {
        await withSetVectors([
          Vector({'a': 0x23, 'b': 0xf}, {'c': 0xf3}),
          Vector({'a': 0x4a, 'b': 0x5}, {'c': 0x5a}),
        ], 4, 4);
      });
      test('setting in the middle', () async {
        await withSetVectors([
          Vector({'a': 0xff, 'b': 0x0}, {'c': bin('11000011')}),
          Vector(
              {'a': bin('01111110'), 'b': bin('0110')}, {'c': bin('01011010')}),
        ], 2, 4);
      });
    });
  });
  group('LogicValue', () {
    group('extend', () {
      test('extend with same width returns same thing', () {
        var original = LogicValue.ofString('0101xz0101');
        var modified = original.extend(original.width, LogicValue.x);
        expect(modified, equals(original));
      });
      test('extend with less width throws exception', () {
        var original = LogicValue.ofString('0101xz0101');
        expect(() => original.extend(original.width - 2, LogicValue.x),
            throwsException);
      });
      test('extend with more width properly extends', () {
        var original = LogicValue.ofString('0101xz0101');
        var modified = original.extend(original.width + 3, LogicValue.x);
        expect(modified, equals(LogicValue.ofString('xxx0101xz0101')));
      });
      test('zero extend pads 0s', () {
        var original = LogicValue.ofString('0101xz0101');
        var modified = original.zeroExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('0000101xz0101')));
      });
      test('sign extend for positive number pads 0s', () {
        var original = LogicValue.ofString('0101xz0101');
        var modified = original.signExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('0000101xz0101')));
      });
      test('sign extend for negative number pads 1s', () {
        var original = LogicValue.ofString('1101xz0101');
        var modified = original.signExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('1111101xz0101')));
      });
    });

    group('withSet', () {
      test('setting with bigger number throws exception', () {
        var original = LogicValue.ofString('1101xz0101');
        expect(() => original.withSet(0, LogicValue.ofString('00001101xz0101')),
            throwsException);
      });
      test('setting with number in middle overrun throws exception', () {
        var original = LogicValue.ofString('1101xz0101');
        expect(() => original.withSet(7, LogicValue.ofString('1111')),
            throwsException);
      });
      test('setting same width returns only new', () {
        var original = LogicValue.ofString('1101xz0101');
        var newVal = LogicValue.ofString('1111001111');
        var modified = original.withSet(0, newVal);
        expect(modified, equals(newVal));
      });
      test('setting at front', () {
        var original = LogicValue.ofString('1101xz0101');
        var newVal = LogicValue.ofString('1111');
        var modified = original.withSet(0, newVal);
        expect(modified, equals(LogicValue.ofString('1101xz1111')));
      });
      test('setting at end', () {
        var original = LogicValue.ofString('xxxxxz0101');
        var newVal = LogicValue.ofString('1111');
        var modified = original.withSet(6, newVal);
        expect(modified, equals(LogicValue.ofString('1111xz0101')));
      });
      test('setting in the middle', () {
        var original = LogicValue.ofString('xxxxxxxxxx');
        var newVal = LogicValue.ofString('1111');
        var modified = original.withSet(3, newVal);
        expect(modified, equals(LogicValue.ofString('xxx1111xxx')));
      });
    });
  });
}
