// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_array.dart
// Definition of multi-dimensional logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'values.dart';

/// A shaped [LogicValue] containing fixed-width [LogicValue] array elements.
///
/// The nested constructor infers shape and element width. Use
/// [LogicValueArray.fromFlat] when values are already row-major or when an
/// empty array requires explicit shape and width metadata.
class LogicValueArray extends TypedLogicValueArray<LogicValue> {
  /// Creates a value array from nested [values].
  factory LogicValueArray(List<Object?> values) {
    final nested =
        _parseNestedArray<LogicValue>(values, argumentName: 'values');
    if (nested.values.isEmpty) {
      throw ArgumentError.value(values, 'values',
          'Cannot infer elementWidth from empty input; use fromFlat.');
    }
    final elementWidth = nested.values.first.width;
    _validateElementWidths(nested.values, elementWidth, 'values');
    return LogicValueArray._stored(
        nested.dimensions, elementWidth, nested.values);
  }

  /// Creates a value array from row-major [values].
  ///
  /// For nonempty input, [elementWidth] defaults to the width of the first
  /// value and all values must have that width. Empty input requires an
  /// explicit [elementWidth].
  factory LogicValueArray.fromFlat(
      List<int> dimensions, Iterable<LogicValue> values,
      {int? elementWidth}) {
    final normalizedDimensions = _validateValueArrayDimensions(dimensions);
    final packedValues = values.toList(growable: false);
    _validateValueCount(normalizedDimensions, packedValues.length, 'values');
    if (packedValues.isEmpty && elementWidth == null) {
      throw ArgumentError.value(
          values, 'values', 'An elementWidth is required for empty input.');
    }
    final resolvedElementWidth = elementWidth ?? packedValues.first.width;
    _validateValueArrayElementWidth(resolvedElementWidth);
    _validateElementWidths(packedValues, resolvedElementWidth, 'values');
    return LogicValueArray._stored(
        normalizedDimensions, resolvedElementWidth, packedValues);
  }

  /// Creates an empty, zero-width value array.
  factory LogicValueArray.empty() =>
      LogicValueArray.fromFlat(const [0], const [], elementWidth: 0);

  /// Generates values from row-major multidimensional indices.
  factory LogicValueArray.generate(
      List<int> dimensions, LogicValue Function(List<int> indices) generator,
      {int? elementWidth}) {
    final normalizedDimensions = _validateValueArrayDimensions(dimensions);
    final values = [
      for (var index = 0;
          index < _valueArrayLength(normalizedDimensions);
          index++)
        generator(_valueArrayIndices(normalizedDimensions, index)),
    ];
    return LogicValueArray.fromFlat(
      normalizedDimensions,
      values,
      elementWidth: elementWidth,
    );
  }

  /// Creates a value array from nested integer [values].
  factory LogicValueArray.fromInts(
    List<Object?> values, {
    required int elementWidth,
  }) {
    final nested = _parseNestedArray<int>(values, argumentName: 'values');
    if (nested.values.isEmpty) {
      throw ArgumentError.value(values, 'values',
          'Cannot infer dimensions from empty input; use fromFlatInts.');
    }
    return LogicValueArray.fromFlat(
      nested.dimensions,
      nested.values.map((value) => LogicValue.ofInt(value, elementWidth)),
      elementWidth: elementWidth,
    );
  }

  /// Creates a value array from flat row-major integer [values].
  factory LogicValueArray.fromFlatInts(
          List<int> dimensions, Iterable<int> values,
          {required int elementWidth}) =>
      LogicValueArray.fromFlat(
        dimensions,
        values.map((value) => LogicValue.ofInt(value, elementWidth)),
        elementWidth: elementWidth,
      );

  /// Stacks equally shaped arrays along a new outer dimension.
  factory LogicValueArray.stack(Iterable<LogicValueArray> arrays) {
    final slices = arrays.toList(growable: false);
    if (slices.isEmpty) {
      throw ArgumentError.value(arrays, 'arrays', 'Must not be empty.');
    }

    final first = slices.first;
    slices.skip(1).forEach(first._checkStackCompatible);
    return LogicValueArray._stored(
      [slices.length, ...first.dimensions],
      first.elementWidth,
      slices.expand((slice) => slice.arrayValues).toList(growable: false),
    );
  }

  /// Stores [values] that are already-normalized packed inputs using the
  /// identity codec.
  ///
  /// The semantic and packed representations are the same for
  /// [LogicValueArray], so this constructor avoids re-encoding them.
  LogicValueArray._stored(
    List<int> dimensions,
    int elementWidth,
    List<LogicValue> values,
  ) : super._normalized(
          dimensions,
          elementWidth,
          values,
          values,
          LogicValueCodec.logicValue,
        );

  @override
  Iterable<LogicValueArray> get majorSlices =>
      super.majorSlices.cast<LogicValueArray>();

  @override
  LogicValueArray map(LogicValue Function(LogicValue value) transform) =>
      LogicValueArray.fromFlat(
        dimensions,
        arrayValues.map(transform),
        elementWidth: elementWidth,
      );

  @override
  LogicValueArray indexedMap(
    LogicValue Function(List<int> indices, LogicValue value) transform,
  ) =>
      LogicValueArray.fromFlat(
        dimensions,
        indexedValues.map((entry) => transform(entry.$1, entry.$2)),
        elementWidth: elementWidth,
      );

  @override
  LogicValueArray reshape(List<int> newDimensions) =>
      super.reshape(newDimensions) as LogicValueArray;

  @override
  LogicValueArray transpose2D() => super.transpose2D() as LogicValueArray;

  @override
  LogicValueArray _createStored(
    List<int> dimensions,
    List<LogicValue> arrayValues,
    List<LogicValue> packedElements,
  ) =>
      LogicValueArray._stored(dimensions, elementWidth, packedElements);
}
