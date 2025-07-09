// Copyright (C) 2023 Intel Corporation
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
  _IterableRemovableElement<T>? _patrol;

  int get size => _size;
  int _size = 0;

  final bool Function(T item)? removeWhere;

  IterableRemovableQueue({this.removeWhere});

  /// Removes all elements that should be removed up until the first element
  /// that should not be, then leaves the [_patrol] pointer there.
  void _runPatrol() {
    if (isEmpty) {
      return;
    }

    if (removeWhere == null) {
      // Nothing to remove.
      return;
    }

    _patrol ??= _first;

    assert(_patrol != null, 'Patrol pointer should not be null by here.');

    _IterableRemovableElement<T>? previous;
    while (_patrol != null) {
      if (removeWhere != null && removeWhere!(_patrol!.item)) {
        previous?.next = _patrol!.next;

        if (_patrol == _first) {
          _first = _patrol!.next;
        } else if (_patrol == _last) {
          _last = previous;
        }
        _size--;
      } else {
        // stop patrolling once we find an element that should not be removed
        _patrol = _patrol!.next;
        break;
      }

      _patrol = _patrol!.next;
    }
  }

  /// Adds a new item to the end of the queue.
  void add(T item) {
    if (removeWhere != null && removeWhere!(item)) {
      // If the item should be removed, we don't add it.
      return;
    }

    final newElement = _IterableRemovableElement<T>(item);
    if (isEmpty) {
      _first = newElement;
      _last = _first;
    } else {
      _last!.next = newElement;
      _last = newElement;
    }
    _size++;

    // every time we add, we should do some patrol work
    _runPatrol();
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
        previous?.next = element.next;

        if (element == _first) {
          _first = element.next;
        } else if (element == _last) {
          _last = previous;
        }

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
