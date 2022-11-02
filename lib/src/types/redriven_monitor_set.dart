/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// redriven_monitor_set.dart
/// A set that monitor for any redriven signal or type
///
/// 2022 November 2
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///
import 'dart:collection';
import 'dart:core';

import 'package:collection/collection.dart';

/// A collection Set that monitor for redriven type or signal
///
/// [RedrivenMonitorSet] can be used if duplicate element are needed to be
/// catch for certain usage.
class RedrivenMonitorSet<T> extends SetBase<T> {
  final Set<T> _set = <T>{};
  final Set<T> _duplicates = <T>{};

  @override
  bool add(T value) {
    if (_set.contains(value)) {
      _duplicates.add(value);
    }

    return _set.add(value);
  }

  /// The duplicate members in the collection
  ///
  /// Returns an [UnmodifiableSetView] if the collection contains duplicates
  UnmodifiableSetView<T> get getDuplicates => UnmodifiableSetView(_duplicates);

  /// Returns `true` if collection contains duplicates
  bool get isDuplicates => _duplicates.isNotEmpty;

  @override
  bool contains(Object? element) => _set.contains(element);

  @override
  Iterator<T> get iterator => _set.iterator;

  @override
  int get length => _set.length;

  @override
  T? lookup(Object? element) => _set.lookup(element);

  @override
  bool remove(Object? value) => _set.remove(value);

  @override
  Set<T> toSet() => _set;
}
