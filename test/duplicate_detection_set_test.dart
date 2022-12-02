/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// duplicate_detection_set_test.dart
/// Unit tests for DuplicateDetectionSet
///
/// 2022 November 11
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/src/collections/duplicate_detection_set.dart';
import 'package:test/test.dart';

void main() {
  group('Add Function: ', () {
    test(
        'should return duplicates if duplicate value exists '
        'through addAll method', () async {
      final testDuplicateSet = DuplicateDetectionSet<int>()..addAll([1, 2, 1]);

      expect(testDuplicateSet.hasDuplicates, equals(true));
      expect(testDuplicateSet.duplicates, equals({1}));
    });
    test(
        'should return duplicates if duplicate value exists through add method',
        () async {
      final testDuplicateSet = DuplicateDetectionSet<int>()
        ..addAll([1, 2, 3])
        ..add(1);

      expect(testDuplicateSet.hasDuplicates, equals(true));
      expect(testDuplicateSet.duplicates, equals({1}));
    });
  });

  group('remove function: ', () {
    test('should return value if removed value are not duplicate', () async {
      final testDuplicateSet = DuplicateDetectionSet<int>()..addAll([3, 1, 2]);
      expect(testDuplicateSet.remove(1), equals(true));
    });
    test('should return exception if removed value that are duplicate',
        () async {
      final testDuplicateSet = DuplicateDetectionSet<int>()
        ..addAll([3, 1, 2, 1]);
      expect(() {
        testDuplicateSet.remove(1);
      }, throwsException);
    });
  });
}
