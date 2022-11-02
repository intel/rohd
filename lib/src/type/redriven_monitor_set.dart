import 'dart:collection';
import 'dart:core';

import 'package:collection/collection.dart';

/// Stackoverflow: https://stackoverflow.com/questions/14441620/custom-collection-in-dart
class RedrivenMonitorSet<T> extends SetBase<T> {
  final Set<T> _set = <T>{};
  final Set<T> _duplicate = <T>{};

  @override
  bool add(dynamic value) {
    if (_set.contains(value)) {
      _duplicate.add(value as T);
    }

    return _set.add(value as T);
  }

  /// create a UnmodifiableSetView (like getter)
  UnmodifiableSetView<T> get duplicate =>
      UnmodifiableSetView(_duplicate.toSet());

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
