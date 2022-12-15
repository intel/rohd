/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// traverseable_collection.dart
/// Efficient implementation of a set-like datastructure that also has fast
/// index access
///
/// 2021 July 13
/// Author: Max Korbel <max.korbel@intel.com>
///

/***/

/// A limited type of collection that has very fast index access and [contains].
///
/// This collection stores all data twice: once in a [Set] and once in a [List].
/// For index access, it uses the [List].  For [contains()], it uses the [Set].
/// Other operations like [add()] and [remove()] pay the penalty of performing
/// the operation twice, once oneach collection.
///
/// In situations where it is necessary to iterate through and frequently access
/// elements by index, but also check whether a certain element is contained
/// wihin it, and there are many elements, this implementation is substantially
/// faster than using either a [Set] or a [List].
class TraverseableCollection<T> {
  final Set<T> _set = <T>{};
  final List<T> _list = <T>[];

  /// The number of objects in this collection.
  ///
  /// The valid indices are 0 through [length] - 1.
  int get length => _list.length;

  /// Adds an element to the collection.
  void add(T item) {
    if (!contains(item)) {
      _list.add(item);
      _set.add(item);
    }
  }

  /// Adds all elements in [items] to the collection.
  void addAll(Iterable<T> items) {
    items.forEach(add);
  }

  /// Removes [item] from the collection.
  ///
  /// Returns true if [item] was in the collection, and false if not.
  /// The method has no effect if [item] was not in the collection.
  bool remove(T item) {
    // assume no duplicates in _list
    _list.remove(item);
    return _set.remove(item);
  }

  /// The object at the given [index] in the collection.
  ///
  /// The [index] must be a valid index of this collection, which means that
  /// [index] must be non-negative and less than [length].
  T operator [](int index) => _list[index];

  /// Whether [item] is in the collection.
  bool contains(T item) => _set.contains(item);
}
