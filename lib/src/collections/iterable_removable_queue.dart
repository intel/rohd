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

  /// Adds a new item to the end of the queue.
  void add(T item) {
    final newElement = _IterableRemovableElement<T>(item);
    if (_first == null) {
      _first = newElement;
      _last = _first;
    } else {
      _last!.next = newElement;
      _last = newElement;
    }
  }

  /// Indicates whether there are no items in the queue.
  bool get isEmpty => _first == null;

  /// Removes all items from this queue.
  void clear() {
    _first = null;
    _last = null;
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

    other.clear();
  }

  /// Iterates through all items in the queue, removing any which are indicated
  /// by [removeWhere], and performing [action] on the rest.
  void iterate(
      {void Function(T item)? action, bool Function(T item)? removeWhere}) {
    if (isEmpty) {
      return;
    }

    var element = _first;
    _IterableRemovableElement<T>? previous;
    while (element != null) {
      if (removeWhere != null && removeWhere(element.item)) {
        previous?.next = element.next;

        if (element == _first) {
          _first = element.next;
        } else if (element == _last) {
          _last = previous;
        }
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
