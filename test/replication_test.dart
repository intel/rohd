/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// replication_test.dart
/// Unit tests for extend and withSet operations
///
/// 2023 Jan 18
/// Author: Akshay Wankhede <akshay.wankhede@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ReplicationOpModule extends Module {
  ReplicationOpModule(Logic a, int multiplier) {
    final newWidth = a.width * multiplier;
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: newWidth < 1 ? a.width : newWidth);

    b <= a.replicate(multiplier);
  }
}

void main() {
  group('Logic', () {
    tearDown(Simulator.reset);
    group('replicate', () {
      Future<void> replicateVectors(List<Vector> vectors, int multiplier,
          {int originalWidth = 8}) async {
        final mod =
            ReplicationOpModule(Logic(width: originalWidth), multiplier);
        await mod.build();
        await SimCompare.checkFunctionalVector(mod, vectors);
        final simResult = SimCompare.iverilogVector(mod, vectors);
        expect(simResult, equals(true));
      }

      test('multiply by a multiplier <1 throws exception', () async {
        expect(
            () => replicateVectors([
                  Vector({'a': 0}, {'b': 0})
                ], 0, originalWidth: 4),
            throwsException);
        expect(() => replicateVectors([], -1), throwsException);
      });

      test('multiply by 1 returns same thing', () async {
        await replicateVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xf}, {'b': 0xf}),
          Vector({'a': 0x5}, {'b': 0x5}),
        ], 1, originalWidth: 4);
      });

      test('multiply by 2 replicates the input signal twice', () async {
        await replicateVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xf}, {'b': 0xff}),
          Vector({'a': 0x5}, {'b': 0x55}),
        ], 2, originalWidth: 4);
      });

      test('multiply by 3 replicates the input signal thrice', () async {
        await replicateVectors([
          Vector({'a': 0}, {'b': 0}),
          Vector({'a': 0xf}, {'b': 0xfff}),
          Vector({'a': 0x5}, {'b': 0x555}),
        ], 3, originalWidth: 4);
      });

      test('LogicValue.replicate tests', () async {
        expect(LogicValue.one.replicate(2).toString(includeWidth: false),
            equals('11'));
        expect(LogicValue.zero.replicate(2).toString(includeWidth: false),
            equals('00'));
        expect(LogicValue.x.replicate(2).toString(includeWidth: false),
            equals('xx'));
        expect(LogicValue.z.replicate(2).toString(includeWidth: false),
            equals('zz'));
        expect(
            LogicValue.ofString('1011')
                .replicate(2)
                .toString(includeWidth: false),
            equals('10111011'));
        expect(() => LogicValue.ofString('1011').replicate(0), throwsException);
        expect(
            () => LogicValue.ofString('1011').replicate(-2), throwsException);
      });
    });
  });
}
