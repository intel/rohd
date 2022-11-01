import 'dart:collection';
import 'dart:core';

/// Stackoverflow: https://stackoverflow.com/questions/14441620/custom-collection-in-dart
class ConditionalSet<Logic> extends SetBase<dynamic> {
  Set<Logic> _set = <Logic>{};

  /// initialization
  ConditionalSet(List<Logic>? init) {
    if (init != null) {
      final allDrivenSignals = <Logic>[];
      for (final element in init) {
        allDrivenSignals.add(element);
      }
      if (allDrivenSignals.length != allDrivenSignals.toSet().length) {
        final alreadySet = <Logic>{};
        final redrivenSignals = <Logic>{};
        for (final signal in allDrivenSignals) {
          if (alreadySet.contains(signal)) {
            redrivenSignals.add(signal);
          }
          alreadySet.add(signal);
        }
        throw Exception('Sequential drove the same signal(s) multiple times:'
            ' $redrivenSignals.');
      }
      _set = init.toSet();
    }
  }

  @override
  bool add(dynamic value) {
    if (value is Logic && value != null) {
      if (_set.contains(value)) {
        throw Exception('Sequential drove the same signal(s) multiple times:'
            ' $value.');
      }
    }
    return _set.add(value as Logic);
  }

  @override
  bool contains(Object? element) => _set.contains(element);

  @override
  Iterator<Logic> get iterator => _set.iterator;

  @override
  int get length => _set.length;

  @override
  Logic? lookup(Object? element) => _set.lookup(element);

  @override
  bool remove(Object? value) => _set.remove(value);

  @override
  Set<Logic> toSet() => _set;
}
