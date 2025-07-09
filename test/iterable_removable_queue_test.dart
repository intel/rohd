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

class LateRemovable {
  bool doRemove = false;
  final int i;
  LateRemovable(this.i);
}

void main() {
  group('iterable removable queue', () {
    const numItems = 100;
    IterableRemovableQueue<int> buildQueue(
        {bool Function(int item)? removeWhere}) {
      final q = IterableRemovableQueue<int>(removeWhere: removeWhere);
      for (var i = 0; i < numItems; i++) {
        q.add(i);
      }
      return q;
    }

    int getCount<T>(IterableRemovableQueue<T> q) {
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
        final q = buildQueue(removeWhere: (i) => i.isEven)..iterate();
        expect(getCount(q), numItems / 2);
        expect(q.isEmpty, false);
      });

      test('remove odd', () {
        final q = buildQueue(removeWhere: (i) => i.isOdd)..iterate();
        expect(getCount(q), numItems / 2);
        expect(q.isEmpty, false);
      });

      test('remove all', () {
        final q = buildQueue(removeWhere: (i) => true)..iterate();
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

    test('size', () {
      final q = buildQueue();
      expect(getCount(q), numItems);
      expect(q.size, numItems);
    });

    group('patrol', () {
      test('patrol removes even when added', () {
        final q = buildQueue(removeWhere: (i) => i.isEven);
        expect(q.size, numItems / 2);
        expect(q.isEmpty, false);
      });

      test('patrol removes later when status changes', () {
        final q = IterableRemovableQueue<LateRemovable>(
          removeWhere: (item) => item.doRemove,
        );
        final items = <LateRemovable>[];
        for (var i = 0; i < numItems; i++) {
          final item = LateRemovable(i);
          items.add(item);
          q.add(item);
        }

        q.iterate();

        expect(getCount(q), numItems);
        expect(q.isEmpty, false);
        expect(q.size, numItems);

        // Now change the status of all items to be removed.
        for (final item in items) {
          if (item.i % 3 == 0) {
            item.doRemove = true;
          }
        }

        // now add more, and make sure patrol is removing things too
        for (var i = numItems; i < numItems * 2; i++) {
          final item = LateRemovable(i);
          items.add(item);
          q.add(item);
        }

        expect(q.size, lessThan(numItems + numItems * 0.75));

        q.iterate();

        expect(q.isEmpty, false);
        expect(q.size, numItems + 2 * numItems ~/ 3);
      });
    });
  });
}
