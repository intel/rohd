// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// iterable_removable_queue.dart
// Definition for an optimized queue for signal propagation subscriptions and
// similar applications.
//
// 2023 April 21
// Author: Max Korbel <max.korbel@intel.com>

/// A queue that can be easily iterated through and remove items during
/// iteration.
class IterableRemovableQueue<T> {
  /// The first item in this queue.
  ///
  /// Null if the queue is empty.
  _IterableRemovableElement<T>? _first;

  /// The last item in this queue.
  ///
  /// Null if the queue is empty.
  _IterableRemovableElement<T>? _last;

  /// A pointer to the current element being patrolled for removal.
  ///
  /// On each [add], this pointer will either move forward by one element or
  /// (including wrap-around to [_first]), or will remove a contiguous set of
  /// elements that should be removed according to the [removeWhere] function.
  _IterableRemovableElement<T>? _patrol;

  /// The number of items in this queue.
  int get size => _size;
  int _size = 0;

  /// A function that determines whether an item should be removed from the
  /// queue.
  final bool Function(T item)? removeWhere;

  /// Constructs a new [IterableRemovableQueue] with an optional [removeWhere]
  /// function that determines whether an item should be removed from the queue.
  IterableRemovableQueue({this.removeWhere});

  /// Removes all elements that should be removed up until the first element
  /// that should not be, then leaves the [_patrol] pointer there. Otherwise,
  /// increments the [_patrol] pointer by one element.
  void _runPatrol() {
    if (isEmpty) {
      return;
    }

    if (removeWhere == null) {
      // Nothing to remove.
      return;
    }

    if (_first == _last && removeWhere!(_first!.item)) {
      // if size is 1 and its removable, then we can just clear the queue and be
      // done with it
      clear();
      return;
    }

    _IterableRemovableElement<T>? previous;
    if (_patrol == null) {
      // If we have no patrol pointer, we start at the first element.
      previous = null;
      _patrol = _first;
    } else {
      // If we have a patrol pointer, we start at the next element.
      previous = _patrol;
      _patrol = _patrol!.next;
    }

    while (_patrol != null) {
      if (removeWhere!(_patrol!.item)) {
        assert(size > 0, 'Should not be removing if size is already 0.');

        if (_patrol == _first && _first == _last) {
          // if size is 1, then we clear the queue and be done with it
          clear();
          break;
        }

        // Remove the patrol element from the queue.
        previous?.next = _patrol!.next;

        if (_patrol == _first) {
          _first = _patrol!.next;
        } else if (_patrol == _last) {
          _last = previous;
        }

        assert((_first == null) == (_last == null),
            'First and last should be both null or both non-null.');

        // Move the patrol pointer to the next element.
        _patrol = _patrol?.next;

        // If we reached the end of the queue, we should wrap around to the
        // first element.
        _patrol ??= _first;

        _size--;
      } else {
        // stop patrolling once we find an element that should not be removed
        break;
      }
    }
  }

  /// Adds a new item to the end of the queue.
  ///
  /// Also may remove items from the queue if they are indicated by
  /// [removeWhere].
  void add(T item) {
    if (removeWhere != null && removeWhere!(item)) {
      // If the item should be removed, we don't add it.
      return;
    }

    // every time we add, we should do some patrol work. note: important to do
    // this *before* adding the new element so that we don't just look at `last`
    // again, since we won't be removing that! also, run it twice so that we are
    // patrolling faster than adding no matter what!
    _runPatrol();
    _runPatrol();

    final newElement = _IterableRemovableElement<T>(item);
    if (isEmpty) {
      _first = newElement;
      _last = _first;
    } else {
      _last!.next = newElement;
      _last = newElement;
    }
    _size++;
  }

  /// Indicates whether there are no items in the queue.
  bool get isEmpty => _first == null;

  /// Removes all items from this queue.
  void clear() {
    _first = null;
    _last = null;
    _patrol = null;
    _size = 0;
  }

  /// Appends [other] to this without copying any elements and [clear]s [other].
  void takeAll(IterableRemovableQueue<T> other) {
    if (other.isEmpty) {
      return;
    }

    if (isEmpty) {
      _first = other._first;
      _last = other._last;
    } else {
      _last!.next = other._first;
      _last = other._last;
    }

    _size += other.size;

    other.clear();
  }

  /// Iterates through all items in the queue, removing any which are indicated
  /// by [removeWhere], and performing [action] on the rest.
  void iterate({void Function(T item)? action}) {
    // Reset patrol pointer if we are iterating through all.
    _patrol = null;

    if (isEmpty) {
      return;
    }

    var element = _first;
    _IterableRemovableElement<T>? previous;
    while (element != null) {
      if (removeWhere != null && removeWhere!(element.item)) {
        assert(size > 0, 'Should not be removing if size is already 0.');

        previous?.next = element.next;

        if (element == _first && _first == _last) {
          // if size is 1, then we clear the queue and be done with it
          clear();
          break;
        }

        if (element == _first) {
          _first = element.next;
        } else if (element == _last) {
          _last = previous;
        }

        assert((_first == null) == (_last == null),
            'First and last should be both null or both non-null.');

        _size--;
      } else {
        if (action != null) {
          action(element.item);
        }

        previous = element;
      }

      element = element.next;
    }
  }
}

/// One element of a [IterableRemovableQueue].
class _IterableRemovableElement<T> {
  /// The item being tracked by this element.
  final T item;

  /// The next element in the queue.
  _IterableRemovableElement<T>? next;

  /// Constructs an element containing [item].
  _IterableRemovableElement(this.item);
}
