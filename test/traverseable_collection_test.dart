// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// traverseable_collection_test.dart
// Tests for `TraverseableCollection`.
//
// 2024 June 12
// Author: Max Korbel <max.korbel@intel.com>

// ignore_for_file: cascade_invocations

import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:test/test.dart';

void main() {
  test('simple traverseable collection usage', () {
    final c = TraverseableCollection<int>();

    c.add(10);

    c.addAll([1, 2, 3]);

    expect(c.length, 4);

    final removed = c.remove(2);
    expect(removed, isTrue);

    final removedAgain = c.remove(2);
    expect(removedAgain, isFalse);

    expect(c.length, 3);

    expect(c[0], 10);
    expect(c[1], 1);
    expect(c[2], 3);

    expect(c.contains(10), isTrue);
    expect(c.contains(3), isTrue);

    for (final item in c) {
      expect(c.contains(item), isTrue);
    }

    expect(c.isEmpty, isFalse);
  });

  test('unmodifiable traverseable collection cannot be changed', () {
    final c = TraverseableCollection<int>();
    final v = UnmodifiableTraversableCollectionView(c);

    c.addAll([1, 2, 3]);

    expect(() => v.add(4), throwsUnsupportedError);
    expect(() => v.addAll([5, 6]), throwsUnsupportedError);
    expect(() => v.remove(1), throwsUnsupportedError);

    expect(v.length, 3);
    expect(v[0], 1);
    expect(v.contains(2), isTrue);
  });
}
