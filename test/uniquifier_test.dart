// Copyright (C) 2023-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// uniquifier_test.dart
// Tests for the Uniquifier
//
// 2023 November 3
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:test/test.dart';

void main() {
  test('Using same reserved name twice throws', () {
    final uniq = Uniquifier(reservedNames: {'apple'})
      ..getUniqueName(initialName: 'apple', reserved: true);

    expect(() => uniq.getUniqueName(initialName: 'apple', reserved: true),
        throwsA(isA<UnavailableReservedNameException>()));
  });

  test('uniquify name if requested twice', () {
    final uniq = Uniquifier();
    final name1 = uniq.getUniqueName(initialName: 'apple');
    final name2 = uniq.getUniqueName(initialName: 'apple');
    expect(name1, 'apple');
    expect(name1, isNot(name2));
  });

  test('uniquify name if reserved', () {
    final uniq = Uniquifier(reservedNames: {'apple'});
    final name1 = uniq.getUniqueName(initialName: 'apple');
    final name2 = uniq.getUniqueName(initialName: 'apple', reserved: true);
    expect(name1, isNot('apple'));
    expect(name2, 'apple');
    expect(name1, isNot(name2));
  });

  group('isAvailable', () {
    test('available name', () {
      final uniq = Uniquifier();
      expect(uniq.isAvailable('apple'), isTrue);
    });

    test('taken name', () {
      final uniq = Uniquifier()..getUniqueName(initialName: 'apple');
      expect(uniq.isAvailable('apple'), isFalse);
    });

    test('reserved name not available', () {
      final uniq = Uniquifier(reservedNames: {'apple'});
      expect(uniq.isAvailable('apple'), isFalse);
    });

    test('reserved name available for reserved', () {
      final uniq = Uniquifier(reservedNames: {'apple'});
      expect(uniq.isAvailable('apple', reserved: true), isTrue);
    });

    test('already used reserved name unavailable', () {
      final uniq = Uniquifier(reservedNames: {'apple'})
        ..getUniqueName(initialName: 'apple', reserved: true);
      expect(uniq.isAvailable('apple', reserved: true), isFalse);
    });
  });
}
