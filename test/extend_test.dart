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
    final b = addOutput('b', width: newWidth);
    // Make it debug-able
    if (extendType == ExtendType.zero) {
      b <= a.zeroExtend(newWidth);
    } else {
      b <= a.signExtend(newWidth);
    }
  }
}

class WithSetModule extends Module {
  WithSetModule(Logic a, int startIndex, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final c = addOutput('c', width: a.width);

    c <= a.withSet(startIndex, b);
  }
}

void main() {
  group('Logic', () {
    tearDown(() async {
      await Simulator.reset();
    });

    group('extend', () {
      Future<void> extendVectors(
          List<Vector> vectors, int newWidth, ExtendType extendType,
          {int originalWidth = 8}) async {
        final mod =
            ExtendModule(Logic(width: originalWidth), newWidth, extendType);
        await mod.build();
        await SimCompare.checkFunctionalVector(mod, vectors);
        final simResult = SimCompare.iverilogVector(mod, vectors);
        expect(simResult, equals(true));
      }

      test('zero extend with same width returns same thing', () async {
        await extendVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xff}, {'b': 0xff}),
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 8, ExtendType.zero);
      });
      test('zero extend with less width throws exception', () async {
        expect(() => extendVectors([], 6, ExtendType.zero), throwsException);
      });
      test('sign extend with same width returns same thing', () async {
        await extendVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xff}, {'b': 0xff}),
          Vector({'a': 0x5a}, {'b': 0x5a}),
        ], 8, ExtendType.sign);
      });
      test('sign extend with less width throws exception', () async {
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
      test('sign extend for invalid Logic pads LogicValue.x', () async {
        await extendVectors([
          Vector({'a': LogicValue.ofString('x0100100')},
              {'b': LogicValue.ofString('xxxxx0100100')}),
        ], 12, ExtendType.sign);
      });
      test('sign extend single bit(0) pads 0s', () async {
        await extendVectors([
          Vector({'a': LogicValue.zero}, {'b': 0x000}),
        ], 12, ExtendType.sign, originalWidth: 1);
      });
      test('sign extend single bit(1) pads 0s', () async {
        await extendVectors([
          Vector({'a': LogicValue.one}, {'b': 0xfff}),
        ], 12, ExtendType.sign, originalWidth: 1);
      });
    });

    group('withSet', () {
      Future<void> withSetVectors(
          List<Vector> vectors, int startIndex, int updateWidth) async {
        final mod = WithSetModule(
            Logic(width: 8), startIndex, Logic(width: updateWidth));
        await mod.build();
        await SimCompare.checkFunctionalVector(mod, vectors);
        final simResult = SimCompare.iverilogVector(mod, vectors);
        expect(simResult, equals(true));
      }

      test('setting with bigger number throws exception', () async {
        expect(() => withSetVectors([], 0, 9), throwsException);
      });
      test('setting with number in middle overrun throws exception', () async {
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
        final original = LogicValue.ofString('0101xz0101');
        final modified = original.extend(original.width, LogicValue.x);
        expect(modified, equals(original));
      });
      test('extend with less width throws exception', () {
        final original = LogicValue.ofString('0101xz0101');
        expect(() => original.extend(original.width - 2, LogicValue.x),
            throwsException);
      });
      test('extend with more width properly extends', () {
        final original = LogicValue.ofString('0101xz0101');
        final modified = original.extend(original.width + 3, LogicValue.x);
        expect(modified, equals(LogicValue.ofString('xxx0101xz0101')));
      });
      test('zero extend pads 0s', () {
        final original = LogicValue.ofString('0101xz0101');
        final modified = original.zeroExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('0000101xz0101')));
      });
      test('sign extend for positive number pads 0s', () {
        final original = LogicValue.ofString('0101xz0101');
        final modified = original.signExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('0000101xz0101')));
      });
      test('sign extend for negative number pads 1s', () {
        final original = LogicValue.ofString('1101xz0101');
        final modified = original.signExtend(original.width + 3);
        expect(modified, equals(LogicValue.ofString('1111101xz0101')));
      });
    });

    group('withSet', () {
      test('setting with bigger number throws exception', () {
        final original = LogicValue.ofString('1101xz0101');
        expect(() => original.withSet(0, LogicValue.ofString('00001101xz0101')),
            throwsException);
      });
      test('setting with number in middle overrun throws exception', () {
        final original = LogicValue.ofString('1101xz0101');
        expect(() => original.withSet(7, LogicValue.ofString('1111')),
            throwsException);
      });
      test('setting same width returns only new', () {
        final original = LogicValue.ofString('1101xz0101');
        final newVal = LogicValue.ofString('1111001111');
        final modified = original.withSet(0, newVal);
        expect(modified, equals(newVal));
      });
      test('setting at front', () {
        final original = LogicValue.ofString('1101xz0101');
        final newVal = LogicValue.ofString('1111');
        final modified = original.withSet(0, newVal);
        expect(modified, equals(LogicValue.ofString('1101xz1111')));
      });
      test('setting at end', () {
        final original = LogicValue.ofString('xxxxxz0101');
        final newVal = LogicValue.ofString('1111');
        final modified = original.withSet(6, newVal);
        expect(modified, equals(LogicValue.ofString('1111xz0101')));
      });
      test('setting in the middle', () {
        final original = LogicValue.ofString('xxxxxxxxxx');
        final newVal = LogicValue.ofString('1111');
        final modified = original.withSet(3, newVal);
        expect(modified, equals(LogicValue.ofString('xxx1111xxx')));
      });
    });
  });
}
