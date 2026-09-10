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
class LogicValueArray extends TypedValueArray<LogicValue> {
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

  /// Creates a value array from row-major [values] and explicit metadata.
  factory LogicValueArray.fromFlat(
    List<int> dimensions,
    int elementWidth,
    Iterable<LogicValue> values,
  ) {
    final normalizedDimensions = _validateValueArrayDimensions(dimensions);
    _validateValueArrayElementWidth(elementWidth);
    final packedValues = values.toList(growable: false);
    _validateValueCount(normalizedDimensions, packedValues.length, 'values');
    _validateElementWidths(packedValues, elementWidth, 'values');
    return LogicValueArray._stored(
        normalizedDimensions, elementWidth, packedValues);
  }

  /// Creates an empty, zero-width value array.
  factory LogicValueArray.empty() =>
      LogicValueArray.fromFlat(const [0], 0, const []);

  /// Generates values from row-major multidimensional indices.
  factory LogicValueArray.generate(
    List<int> dimensions,
    int elementWidth,
    LogicValue Function(List<int> indices) generator,
  ) {
    final normalizedDimensions = _validateValueArrayDimensions(dimensions);
    return LogicValueArray.fromFlat(
      normalizedDimensions,
      elementWidth,
      Iterable.generate(
        _valueArrayLength(normalizedDimensions),
        (index) => generator(
          _valueArrayIndices(normalizedDimensions, index),
        ),
      ),
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
      elementWidth,
      nested.values.map((value) => LogicValue.ofInt(value, elementWidth)),
    );
  }

  /// Creates a value array from flat row-major integer [values].
  factory LogicValueArray.fromFlatInts(
    List<int> dimensions,
    int elementWidth,
    Iterable<int> values,
  ) =>
      LogicValueArray.fromFlat(
        dimensions,
        elementWidth,
        values.map((value) => LogicValue.ofInt(value, elementWidth)),
      );

  /// Captures the current values of a hardware [LogicArray].
  factory LogicValueArray.fromLogicArray(
          TypedLogicArray<Logic, LogicValue> values) =>
      LogicValueArray.fromFlat(
        values.dimensions,
        values.elementWidth,
        values.arrayElements.map((element) => element.value),
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
          dimensions, elementWidth, arrayValues.map(transform));

  @override
  LogicValueArray indexedMap(
    LogicValue Function(List<int> indices, LogicValue value) transform,
  ) =>
      LogicValueArray.fromFlat(
        dimensions,
        elementWidth,
        indexedValues.map((entry) => transform(entry.$1, entry.$2)),
      );

  @override
  LogicValueArray mapMajorSlices(
    TypedValueArray<LogicValue> Function(TypedValueArray<LogicValue> slice)
        transform,
  ) {
    final transformed = majorSlices.map(transform).toList(growable: false);
    if (transformed.isEmpty) {
      throw StateError('Cannot infer a mapped shape from zero major slices.');
    }
    final first = transformed.first;
    transformed.skip(1).forEach(first._checkStackCompatible);
    return LogicValueArray._stored(
      [transformed.length, ...first.dimensions],
      first.elementWidth,
      transformed
          .expand((slice) => slice._packedElements)
          .toList(growable: false),
    );
  }

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
