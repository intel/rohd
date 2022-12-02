/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// redriven_monitor_set.dart
/// A set that monitor for duplication.
///
/// 2022 November 2
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
import 'dart:collection';
import 'dart:core';

import 'package:collection/collection.dart';

/// A Set collection that monitor for duplication.
///
/// The [DuplicateDetectionSet] is used to identify
/// duplicate elements in the Set.
class DuplicateDetectionSet<T> extends SetBase<T> {
  /// The [Set] which contains unique values.
  final Set<T> _set = <T>{};

  /// The [Set] which contains duplicate values.
  final Set<T> _duplicates = <T>{};

  @override
  bool add(T value) {
    if (_set.contains(value)) {
      _duplicates.add(value);
    }

    return _set.add(value);
  }

  @override
  void addAll(Iterable<T> elements) {
    elements.forEach(add);
  }

  /// The duplicate members in the collection
  ///
  /// Returns an [UnmodifiableSetView] from DuplicateDetectionSet collection
  Set<T> get duplicates => UnmodifiableSetView(_duplicates);

  /// Returns `true` if collection contains duplicates
  bool get hasDuplicates => _duplicates.isNotEmpty;

  @override
  bool contains(Object? element) => _set.contains(element);

  @override
  Iterator<T> get iterator => _set.iterator;

  @override
  int get length => _set.length;

  @override
  T? lookup(Object? element) => _set.lookup(element);

  /// Removes value from [DuplicateDetectionSet] collection.
  ///
  /// The [value] in [DuplicateDetectionSet] must not contain duplicates.
  /// An [Exception] will be thrown if duplicates [value] found.
  @override
  bool remove(Object? value) {
    if (_set.contains(value) && _duplicates.contains(value)) {
      throw Exception('Duplication value detected inside Set!');
    }
    return _set.remove(value);
  }

  @override
  Set<T> toSet() => _set;
}
