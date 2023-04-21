// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// iterable_removable_queue_test.dart
// Tests for `IterableRemovableQueue`.
//
// 2023 April 21
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/collections/iterable_removable_queue.dart';
import 'package:test/test.dart';

void main() {
  group('iterable removable queue', () {
    const numItems = 100;
    IterableRemovableQueue<int> buildQueue() {
      final q = IterableRemovableQueue<int>();
      for (var i = 0; i < numItems; i++) {
        q.add(i);
      }
      return q;
    }

    int getCount(IterableRemovableQueue<int> q) {
      var count = 0;
      q.iterate(action: (item) {
        count++;
      });
      return count;
    }

    group('forEach', () {
      test('no removal', () {
        final q = buildQueue();
        expect(getCount(q), numItems);
        expect(q.isEmpty, false);
      });

      test('remove even', () {
        final q = buildQueue()..iterate(removeWhere: (i) => i.isEven);
        expect(getCount(q), numItems / 2);
        expect(q.isEmpty, false);
      });

      test('remove odd', () {
        final q = buildQueue()..iterate(removeWhere: (i) => i.isOdd);
        expect(getCount(q), numItems / 2);
        expect(q.isEmpty, false);
      });

      test('remove all', () {
        final q = buildQueue()..iterate(removeWhere: (i) => true);
        expect(getCount(q), 0);
        expect(q.isEmpty, true);
      });
    });

    // clear
    test('clear', () {
      final q = buildQueue()..clear();
      expect(getCount(q), 0);
      expect(q.isEmpty, true);
    });

    // takeAll
    test('takeAll', () {
      final q1 = buildQueue();
      final q2 = buildQueue();
      q1.takeAll(q2);
      expect(getCount(q1), numItems * 2);
      expect(q2.isEmpty, true);
    });
  });
}
