// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_array_of.dart
// Definition of typed multi-dimensional logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'signals.dart';

/// Converts semantic values of type [T] to and from packed [LogicValue]s.
class LogicValueCodec<T> {
  /// Converts a packed value into a semantic value.
  final T Function(LogicValue value) decode;

  /// Converts a semantic value into its packed representation.
  final LogicValue Function(T value) encode;

  /// Creates a bidirectional value [decode]/[encode] codec.
  const LogicValueCodec({required this.decode, required this.encode});
}

/// A multidimensional array of semantic values backed by [LogicValue]s.
class LogicValueArrayOf<T> {
  final LogicValueArray _logicValues;
  final List<T> _values;

  /// Codec used at the packed logic boundary.
  final LogicValueCodec<T> codec;

  /// Creates a typed value array from row-major [values].
  factory LogicValueArrayOf(
    List<int> dimensions,
    int elementWidth,
    Iterable<T> values, {
    required LogicValueCodec<T> codec,
  }) {
    final typedValues = List<T>.unmodifiable(values);
    return LogicValueArrayOf._(
        LogicValueArray(
            dimensions, elementWidth, typedValues.map(codec.encode)),
        typedValues,
        codec);
  }

  /// Decodes a packed [LogicValueArray].
  factory LogicValueArrayOf.fromLogicValues(LogicValueArray values,
          {required LogicValueCodec<T> codec}) =>
      LogicValueArrayOf._(values,
          List<T>.unmodifiable(values.flatValues.map(codec.decode)), codec);

  /// Stacks equally shaped typed arrays along a new outer dimension.
  factory LogicValueArrayOf.stack(Iterable<LogicValueArrayOf<T>> arrays) {
    final slices = arrays.toList(growable: false);
    if (slices.isEmpty) {
      throw ArgumentError.value(arrays, 'arrays', 'Must not be empty.');
    }

    final first = slices.first;
    return LogicValueArrayOf(
        [slices.length, ...first.dimensions], first.elementWidth,
        slices.expand((slice) {
      first._checkCompatible(slice);
      return slice.flatValues;
    }), codec: first.codec);
  }

  LogicValueArrayOf._(this._logicValues, this._values, this.codec);

  /// Number of elements at each array level.
  List<int> get dimensions => _logicValues.dimensions;

  /// Width of each packed leaf.
  int get elementWidth => _logicValues.elementWidth;

  /// Number of typed leaves.
  int get length => _logicValues.length;

  /// Typed leaves in row-major order.
  List<T> get flatValues => UnmodifiableListView(_values);

  /// Packed value-domain representation.
  LogicValueArray get logicValues => _logicValues;

  /// Typed values paired with their multidimensional indices.
  Iterable<(List<int>, T)> get indexedValues => _logicValues.indexedValues
      .zipExact(_values)
      .map((entry) => (entry.$1.$1, entry.$2));

  /// Slices along the first dimension.
  Iterable<LogicValueArrayOf<T>> get majorSlices =>
      _logicValues.majorSlices.map(_fromLogicValues);

  /// Returns the typed value at multidimensional [indices].
  T at(List<int> indices) => _values[_logicValues.flatIndexOf(indices)];

  /// Maps typed values while preserving shape and codec.
  LogicValueArrayOf<T> map(T Function(T value) transform) =>
      LogicValueArrayOf(dimensions, elementWidth, _values.map(transform),
          codec: codec);

  /// Maps typed values with their multidimensional indices.
  LogicValueArrayOf<T> indexedMap(
    T Function(List<int> indices, T value) transform,
  ) =>
      LogicValueArrayOf(dimensions, elementWidth,
          indexedValues.map((entry) => transform(entry.$1, entry.$2)),
          codec: codec);

  /// Maps slices along the first dimension and stacks the results.
  LogicValueArrayOf<T> mapMajorSlices(
    LogicValueArrayOf<T> Function(LogicValueArrayOf<T> slice) transform,
  ) =>
      LogicValueArrayOf.stack(majorSlices.map(transform));

  /// Returns a row-major view with new [dimensions].
  LogicValueArrayOf<T> reshape(List<int> dimensions) =>
      LogicValueArrayOf.fromLogicValues(_logicValues.reshape(dimensions),
          codec: codec);

  /// Transposes a two-dimensional typed value array.
  LogicValueArrayOf<T> transpose2D() =>
      LogicValueArrayOf.fromLogicValues(_logicValues.transpose2D(),
          codec: codec);

  /// Creates a [LogicArray] driven by the packed values.
  LogicArray toLogicArray({String? name}) =>
      _logicValues.toLogicArray(name: name);

  /// Drives [target] with the packed values.
  U putInto<U extends LogicArray>(U target) => _logicValues.putInto(target);

  LogicValueArrayOf<T> _fromLogicValues(LogicValueArray values) =>
      LogicValueArrayOf.fromLogicValues(values, codec: codec);

  void _checkCompatible(LogicValueArrayOf<T> other) {
    if (elementWidth != other.elementWidth ||
        !_sameDimensions(dimensions, other.dimensions)) {
      throw ArgumentError.value(
          other.dimensions,
          'arrays',
          'All arrays must have dimensions $dimensions and '
              'elementWidth $elementWidth.');
    }
  }
}
