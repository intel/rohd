// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_array.dart
// Definition of multi-dimensional logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'signals.dart';

/// Value-domain counterpart to [LogicArray].
///
/// Stores fixed-width [LogicValue] leaves with [dimensions] matching the shape
/// used by a [LogicArray]. Values are kept in the same row-major leaf order
/// used by [LogicArray.arrayElements].
class LogicValueArray {
  /// The number of elements at each array level.
  final List<int> dimensions;

  /// Width of each leaf value.
  final int elementWidth;

  final List<LogicValue> _values;

  /// Creates a value array from row-major [values].
  LogicValueArray(
    List<int> dimensions,
    this.elementWidth,
    Iterable<LogicValue> values,
  )   : dimensions = List<int>.unmodifiable(dimensions),
        _values = List<LogicValue>.unmodifiable(values) {
    if (dimensions.isEmpty) {
      throw ArgumentError.value(dimensions, 'dimensions', 'Must not be empty.');
    }
    if (dimensions.any((dimension) => dimension < 0)) {
      throw ArgumentError.value(
          dimensions, 'dimensions', 'Dimensions must be non-negative.');
    }
    if (elementWidth < 0) {
      throw ArgumentError.value(
          elementWidth, 'elementWidth', 'Must be non-negative.');
    }
    if (_values.length != length) {
      throw ArgumentError.value(
          _values.length, 'values', 'Must contain exactly $length values.');
    }
    for (final value in _values) {
      if (value.width != elementWidth) {
        throw ArgumentError.value(
            value, 'values', 'All values must have width $elementWidth.');
      }
    }
  }

  /// Creates an empty zero-width value array.
  LogicValueArray.empty()
      : dimensions = const [0],
        elementWidth = 0,
        _values = const [];

  /// Generates values from row-major multidimensional indices.
  factory LogicValueArray.generate(List<int> dimensions, int elementWidth,
      LogicValue Function(List<int> indices) generator) {
    final length = _lengthFor(dimensions);
    return LogicValueArray(dimensions, elementWidth, [
      for (var index = 0; index < length; index++)
        generator(_indicesFor(dimensions, index))
    ]);
  }

  /// Creates a value array from integer values.
  factory LogicValueArray.fromInts(
          List<int> dimensions, int elementWidth, Iterable<int> values) =>
      LogicValueArray(dimensions, elementWidth,
          values.map((value) => LogicValue.ofInt(value, elementWidth)));

  /// Captures the current values of a [LogicArray].
  factory LogicValueArray.fromLogicArray(LogicArray values) => LogicValueArray(
      values.dimensions,
      values.elementWidth,
      values.arrayElements.map((element) => element.packed.value));

  /// Stacks equally shaped arrays along a new outer dimension.
  factory LogicValueArray.stack(Iterable<LogicValueArray> arrays) {
    final slices = arrays.toList(growable: false);
    if (slices.isEmpty) {
      throw ArgumentError.value(arrays, 'arrays', 'Must not be empty.');
    }

    final first = slices.first;
    for (final slice in slices.skip(1)) {
      first._checkCompatible(slice.dimensions, slice.elementWidth);
    }
    return LogicValueArray([slices.length, ...first.dimensions],
        first.elementWidth, slices.expand((slice) => slice.flatValues));
  }

  /// Number of leaf values.
  int get length => _lengthFor(dimensions);

  /// Row-major leaf values.
  List<LogicValue> get flatValues => UnmodifiableListView(_values);

  /// Row-major values paired with their multidimensional indices.
  Iterable<(List<int>, LogicValue)> get indexedValues => Iterable.generate(
      length, (index) => (_indicesFor(dimensions, index), _values[index]));

  /// Slices along the first dimension.
  Iterable<LogicValueArray> get majorSlices sync* {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }
    final sliceDimensions = dimensions.sublist(1);
    final sliceLength = _lengthFor(sliceDimensions);
    for (var start = 0; start < length; start += sliceLength) {
      yield LogicValueArray(sliceDimensions, elementWidth,
          _values.getRange(start, start + sliceLength));
    }
  }

  /// Returns the value at multidimensional [indices].
  LogicValue at(List<int> indices) => _values[_flatIndex(indices)];

  /// Returns the row-major flat index for multidimensional [indices].
  int flatIndexOf(List<int> indices) => _flatIndex(indices);

  /// Maps this array while preserving dimensions and element width.
  LogicValueArray map(LogicValue Function(LogicValue value) transform) =>
      LogicValueArray(dimensions, elementWidth, _values.map(transform));

  /// Maps this array with row-major multidimensional indices.
  LogicValueArray indexedMap(
    LogicValue Function(List<int> indices, LogicValue value) transform,
  ) =>
      LogicValueArray(dimensions, elementWidth,
          indexedValues.map((entry) => transform(entry.$1, entry.$2)));

  /// Maps slices along the first dimension and stacks the results.
  LogicValueArray mapMajorSlices(
    LogicValueArray Function(LogicValueArray slice) transform,
  ) =>
      LogicValueArray.stack(majorSlices.map(transform));

  /// Returns a row-major view with new [dimensions].
  LogicValueArray reshape(List<int> dimensions) {
    if (_lengthFor(dimensions) != length) {
      throw ArgumentError.value(
          dimensions, 'dimensions', 'Must contain $length values.');
    }
    return LogicValueArray(dimensions, elementWidth, _values);
  }

  /// Transposes a two-dimensional value array.
  LogicValueArray transpose2D() {
    _checkTwoDimensional(dimensions);
    return LogicValueArray.generate([dimensions[1], dimensions[0]],
        elementWidth, (indices) => at([indices[1], indices[0]]));
  }

  /// Creates a [LogicArray] with the same shape and drives it with this value.
  LogicArray toLogicArray({String? name}) =>
      putInto(LogicArray(dimensions, elementWidth, name: name));

  /// Drives [target] with this value array.
  T putInto<T extends LogicArray>(T target) {
    _checkCompatible(target.dimensions, target.elementWidth);
    for (var index = 0; index < _values.length; index++) {
      target.arrayElements[index].put(_values[index]);
    }
    return target;
  }

  void _checkCompatible(List<int> otherDimensions, int otherElementWidth) {
    if (!_sameDimensions(dimensions, otherDimensions) ||
        elementWidth != otherElementWidth) {
      throw ArgumentError.value(otherDimensions, 'target',
          'Must have dimensions $dimensions and elementWidth $elementWidth.');
    }
  }

  int _flatIndex(List<int> indices) {
    if (indices.length != dimensions.length) {
      throw RangeError.range(indices.length, dimensions.length,
          dimensions.length, 'indices.length');
    }

    var index = 0;
    for (var dimension = 0; dimension < dimensions.length; dimension++) {
      final indexAtDimension = indices[dimension];
      if (indexAtDimension < 0 || indexAtDimension >= dimensions[dimension]) {
        throw RangeError.range(indexAtDimension, 0, dimensions[dimension] - 1,
            'indices[$dimension]');
      }
      index = index * dimensions[dimension] + indexAtDimension;
    }
    return index;
  }

  static int _lengthFor(List<int> dimensions) =>
      dimensions.fold(1, (length, dimension) => length * dimension);

  static List<int> _indicesFor(List<int> dimensions, int flatIndex) {
    final indices = List.filled(dimensions.length, 0);
    for (var dimension = dimensions.length - 1; dimension >= 0; dimension--) {
      final size = dimensions[dimension];
      indices[dimension] = size == 0 ? 0 : flatIndex % size;
      flatIndex = size == 0 ? 0 : flatIndex ~/ size;
    }
    return indices;
  }

  static bool _sameDimensions(List<int> left, List<int> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);
}

/// Functional traversal helpers for [LogicArray].
extension LogicArrayTraversal on LogicArray {
  /// Row-major leaves paired with their multidimensional indices.
  Iterable<(List<int>, Logic)> get indexedLeaves => Iterable.generate(
        arrayElements.length,
        (index) => (
          LogicValueArray._indicesFor(dimensions, index),
          arrayElements[index]
        ),
      );

  /// Returns the leaf at multidimensional [indices].
  Logic at(List<int> indices) {
    if (indices.length != dimensions.length) {
      throw RangeError.range(indices.length, dimensions.length,
          dimensions.length, 'indices.length');
    }

    Logic current = this;
    for (var dimension = 0; dimension < indices.length; dimension++) {
      final index = indices[dimension];
      final size = dimensions[dimension];
      if (index < 0 || index >= size) {
        throw RangeError.range(index, 0, size - 1, 'indices[$dimension]');
      }
      current = (current as LogicStructure).elements[index];
    }
    return current;
  }

  /// Connects row-major leaves to [sources], requiring equal lengths.
  LogicArray getsEach(Iterable<Logic> sources) {
    for (final (target, source) in arrayElements.zipExact(sources)) {
      target <= source;
    }
    return this;
  }

  /// Connects each leaf to a value generated from its array indices.
  LogicArray getsGenerated(Logic Function(List<int> indices) generator) {
    for (final (indices, target) in indexedLeaves) {
      target <= generator(indices);
    }
    return this;
  }

  /// Returns a row-major view with new [dimensions].
  LogicArray reshape(List<int> dimensions, {String? name}) {
    if (LogicValueArray._lengthFor(dimensions) != arrayElements.length) {
      throw ArgumentError.value(dimensions, 'dimensions',
          'Must contain ${arrayElements.length} leaves.');
    }
    return LogicArray(dimensions, elementWidth, name: name)
      ..getsEach(arrayElements);
  }

  /// Transposes a two-dimensional logic array.
  LogicArray transpose2D({String? name}) {
    _checkTwoDimensional(dimensions);
    return LogicArray([dimensions[1], dimensions[0]], elementWidth, name: name)
      ..getsGenerated((indices) => at([indices[1], indices[0]]));
  }

  /// Immediate child arrays along the first dimension.
  Iterable<LogicArray> get majorSlices {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }
    return elements.cast<LogicArray>();
  }
}

/// Exact pairwise iteration for functional array wiring.
extension ExactZip<T> on Iterable<T> {
  /// Zips this iterable with [other], throwing when lengths differ.
  Iterable<(T, U)> zipExact<U>(Iterable<U> other) sync* {
    final left = iterator;
    final right = other.iterator;
    while (true) {
      final hasLeft = left.moveNext();
      final hasRight = right.moveNext();
      if (hasLeft != hasRight) {
        throw StateError('Cannot zip iterables of different lengths.');
      }
      if (!hasLeft) {
        return;
      }
      yield (left.current, right.current);
    }
  }
}

/// Splits an iterable of pairs into two lists.
extension Unzip<T, U> on Iterable<(T, U)> {
  /// Unzips pairs while preserving iteration order.
  (List<T>, List<U>) unzip() {
    final left = <T>[];
    final right = <U>[];
    for (final (first, second) in this) {
      left.add(first);
      right.add(second);
    }
    return (left, right);
  }
}

void _checkTwoDimensional(List<int> dimensions) {
  if (dimensions.length != 2) {
    throw StateError('Expected exactly two dimensions, got $dimensions.');
  }
}
