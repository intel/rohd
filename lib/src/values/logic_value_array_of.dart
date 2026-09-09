// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_array_of.dart
// Definition of typed multi-dimensional logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'values.dart';

/// Converts semantic values of type [T] to and from packed [LogicValue]s.
class LogicValueCodec<T> {
  /// Converts a packed value into a semantic value.
  final T Function(LogicValue value) decode;

  final Function _encode;

  /// Creates a bidirectional value [decode]/[encode] codec.
  const LogicValueCodec({
    required this.decode,
    required LogicValue Function(T value) encode,
  }) : _encode = encode;

  /// Converts a semantic [value] into its packed representation.
  LogicValue encode(T value) =>
      (_encode as LogicValue Function(T value))(value);
}

/// A multidimensional array of semantic values backed by packed logic values.
///
/// [arrayValues] contains one value for each position in [dimensions], in
/// row-major order. The ordinary [LogicValue] contract applies to the packed
/// representation: [width] and deprecated `length` count bits, `[]` indexes
/// packed bits, and equality and hashing do not consider shape.
///
/// The nested constructor infers dimensions from its input. The root list
/// always represents an array dimension. Below the root, an object matching [T]
/// is treated as a semantic value before considering whether it is also a list.
/// Use [LogicValueArrayOf.fromFlat] when list-valued semantic data is ambiguous
/// or when empty data requires explicit shape and width metadata.
///
/// Values are normalized through [codec] at construction: each value is
/// encoded and then immediately decoded. The packed representation is
/// authoritative, so lossy codecs expose their normalized semantic values.
class LogicValueArrayOf<T> extends LogicValue {
  /// The number of elements at each array level.
  final List<int> dimensions;

  /// Width of each packed array element.
  final int elementWidth;

  /// Codec used at each packed element boundary.
  final LogicValueCodec<T> codec;

  final List<T> _arrayValues;
  final List<LogicValue> _packedElements;

  /// The ordinary packed representation of this shaped value.
  @override
  final LogicValue packed;

  /// Creates a typed value array from nested [values].
  ///
  /// Empty or ragged nested input is rejected. Use
  /// [LogicValueArrayOf.fromFlat] to construct an empty array because its
  /// element width cannot be inferred.
  factory LogicValueArrayOf(
    List<Object?> values, {
    required LogicValueCodec<T> codec,
  }) {
    final nested = _parseNestedArray<T>(values, argumentName: 'values');
    if (nested.values.isEmpty) {
      throw ArgumentError.value(values, 'values',
          'Cannot infer elementWidth from empty input; use fromFlat.');
    }

    final encoded = nested.values.map(codec.encode).toList(growable: false);
    final elementWidth = encoded.first.width;
    _validateElementWidths(encoded, elementWidth, 'values');
    return LogicValueArrayOf<T>._normalized(
      nested.dimensions,
      elementWidth,
      encoded.map(codec.decode).toList(growable: false),
      encoded,
      codec,
    );
  }

  /// Creates a typed value array from row-major [values] and explicit metadata.
  factory LogicValueArrayOf.fromFlat(
    List<int> dimensions,
    int elementWidth,
    Iterable<T> values, {
    required LogicValueCodec<T> codec,
  }) {
    final normalizedDimensions = _validateValueArrayDimensions(dimensions);
    _validateValueArrayElementWidth(elementWidth);
    final semanticValues = values.toList(growable: false);
    _validateValueCount(normalizedDimensions, semanticValues.length, 'values');
    final encoded = semanticValues.map(codec.encode).toList(growable: false);
    _validateElementWidths(encoded, elementWidth, 'values');
    return LogicValueArrayOf<T>._normalized(
      normalizedDimensions,
      elementWidth,
      encoded.map(codec.decode).toList(growable: false),
      encoded,
      codec,
    );
  }

  /// Decodes the packed elements of [values] with [codec].
  factory LogicValueArrayOf.fromLogicValueArray(
    LogicValueArray values, {
    required LogicValueCodec<T> codec,
  }) =>
      LogicValueArrayOf<T>._normalized(
        values.dimensions,
        values.elementWidth,
        values._packedElements.map(codec.decode).toList(growable: false),
        values._packedElements,
        codec,
      );

  /// Stacks equally shaped arrays along a new outer dimension.
  ///
  /// All arrays must use the identical [LogicValueCodec] instance. Codec
  /// functions cannot be compared for semantic equivalence.
  factory LogicValueArrayOf.stack(Iterable<LogicValueArrayOf<T>> arrays) {
    final slices = arrays.toList(growable: false);
    if (slices.isEmpty) {
      throw ArgumentError.value(arrays, 'arrays', 'Must not be empty.');
    }

    final first = slices.first;
    slices.skip(1).forEach(first._checkStackCompatible);
    return LogicValueArrayOf<T>._normalized(
      [slices.length, ...first.dimensions],
      first.elementWidth,
      slices.expand((slice) => slice._arrayValues).toList(growable: false),
      slices.expand((slice) => slice._packedElements).toList(growable: false),
      first.codec,
    );
  }

  LogicValueArrayOf._normalized(
    List<int> dimensions,
    this.elementWidth,
    List<T> arrayValues,
    List<LogicValue> packedElements,
    this.codec,
  )   : dimensions = List<int>.unmodifiable(dimensions),
        _arrayValues = List<T>.unmodifiable(arrayValues),
        _packedElements = List<LogicValue>.unmodifiable(packedElements),
        packed = LogicValue.ofIterable(packedElements),
        super._(_valueArrayLength(dimensions) * elementWidth) {
    assert(_arrayValues.length == _valueArrayLength(dimensions),
        'Semantic value count must match dimensions.');
    assert(_packedElements.length == _arrayValues.length,
        'Packed and semantic value counts must match.');
    assert(_packedElements.every((value) => value.width == elementWidth),
        'Packed elements must match elementWidth.');
    assert(
        packed.width == width, 'Packed width must match the LogicValue width.');
  }

  /// Number of semantic array elements.
  int get elementCount => _arrayValues.length;

  /// Semantic array elements in row-major order.
  List<T> get arrayValues => _arrayValues;

  /// Values paired with their row-major multidimensional indices.
  Iterable<(List<int>, T)> get indexedValues => Iterable.generate(
        elementCount,
        (index) => (
          _valueArrayIndices(dimensions, index),
          _arrayValues[index],
        ),
      );

  /// Slices along the first dimension.
  Iterable<LogicValueArrayOf<T>> get majorSlices sync* {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }

    final sliceDimensions = dimensions.sublist(1);
    final sliceElementCount = _valueArrayLength(sliceDimensions);
    for (var slice = 0; slice < dimensions.first; slice++) {
      final start = slice * sliceElementCount;
      final end = start + sliceElementCount;
      yield _createStored(
        sliceDimensions,
        _arrayValues.sublist(start, end),
        _packedElements.sublist(start, end),
      );
    }
  }

  /// Returns the semantic value at multidimensional [indices].
  T at(List<int> indices) => _arrayValues[flatIndexOf(indices)];

  /// Returns the row-major flat index for multidimensional [indices].
  int flatIndexOf(List<int> indices) =>
      _valueArrayFlatIndex(dimensions, indices);

  /// Maps semantic values while preserving shape and codec.
  LogicValueArrayOf<T> map(T Function(T value) transform) =>
      LogicValueArrayOf<T>.fromFlat(
        dimensions,
        elementWidth,
        _arrayValues.map(transform),
        codec: codec,
      );

  /// Maps semantic values with their multidimensional indices.
  LogicValueArrayOf<T> indexedMap(
    T Function(List<int> indices, T value) transform,
  ) =>
      LogicValueArrayOf<T>.fromFlat(
        dimensions,
        elementWidth,
        indexedValues.map((entry) => transform(entry.$1, entry.$2)),
        codec: codec,
      );

  /// Maps slices along the first dimension and stacks the results.
  LogicValueArrayOf<T> mapMajorSlices(
    LogicValueArrayOf<T> Function(LogicValueArrayOf<T> slice) transform,
  ) =>
      LogicValueArrayOf<T>.stack(majorSlices.map(transform));

  /// Returns a row-major view with [newDimensions].
  LogicValueArrayOf<T> reshape(List<int> newDimensions) {
    final normalizedDimensions = _validateValueArrayDimensions(newDimensions);
    if (_valueArrayLength(normalizedDimensions) != elementCount) {
      throw ArgumentError.value(newDimensions, 'newDimensions',
          'Must contain $elementCount array elements.');
    }
    return _createStored(normalizedDimensions, _arrayValues, _packedElements);
  }

  /// Transposes this two-dimensional value array.
  LogicValueArrayOf<T> transpose2D() {
    _checkValueArrayIsTwoDimensional(dimensions);
    final newDimensions = [dimensions[1], dimensions[0]];
    final semanticValues = <T>[];
    final packedElements = <LogicValue>[];
    for (var row = 0; row < newDimensions[0]; row++) {
      for (var column = 0; column < newDimensions[1]; column++) {
        final source = flatIndexOf([column, row]);
        semanticValues.add(_arrayValues[source]);
        packedElements.add(_packedElements[source]);
      }
    }
    return _createStored(newDimensions, semanticValues, packedElements);
  }

  /// Creates a [LogicArray] with the same shape and drives it with this value.
  LogicArray toLogicArray({String? name}) =>
      putInto(LogicArray(dimensions, elementWidth, name: name));

  /// Drives a compatible hardware [target] with this shaped value.
  U putInto<U extends LogicArrayOf<Logic>>(U target) {
    _checkHardwareCompatible(target);
    for (var index = 0; index < elementCount; index++) {
      target.arrayElements[index].put(_packedElements[index]);
    }
    return target;
  }

  LogicValueArrayOf<T> _createStored(
    List<int> dimensions,
    List<T> arrayValues,
    List<LogicValue> packedElements,
  ) =>
      LogicValueArrayOf<T>._normalized(
          dimensions, elementWidth, arrayValues, packedElements, codec);

  void _checkStackCompatible(LogicValueArrayOf<T> other) {
    if (!identical(codec, other.codec)) {
      throw ArgumentError.value(
          other.codec, 'arrays', 'All arrays must use the identical codec.');
    }
    if (elementWidth != other.elementWidth ||
        !_sameValueArrayDimensions(dimensions, other.dimensions)) {
      throw ArgumentError.value(
          other.dimensions,
          'arrays',
          'All arrays must have dimensions $dimensions and '
              'elementWidth $elementWidth.');
    }
  }

  void _checkHardwareCompatible(LogicArrayOf<Logic> target) {
    if (elementWidth != target.elementWidth ||
        !_sameValueArrayDimensions(dimensions, target.dimensions)) {
      throw ArgumentError.value(
          target,
          'target',
          'Must have dimensions $dimensions and '
              'elementWidth $elementWidth.');
    }
  }

  @override
  bool _equals(Object other) => other is LogicValue && packed == other.packed;

  @override
  int get _hashCode => packed._hashCode;

  @override
  LogicValue _getIndex(int index) => packed._getIndex(index);

  @override
  LogicValue _getRange(int start, int end) => packed._getRange(start, end);

  @override
  LogicValue get reversed => packed.reversed;

  @override
  bool get isValid => packed.isValid;

  @override
  bool get isFloating => packed.isFloating;

  @override
  int toInt() => packed.toInt();

  @override
  BigInt toBigInt() => packed.toBigInt();

  @override
  LogicValue operator ~() => ~packed;

  @override
  LogicValue _and2(LogicValue other) => packed & other.packed;

  @override
  LogicValue _or2(LogicValue other) => packed | other.packed;

  @override
  LogicValue _xor2(LogicValue other) => packed ^ other.packed;

  @override
  LogicValue _triState2(LogicValue other) => packed.triState(other.packed);

  @override
  LogicValue and() => packed.and();

  @override
  LogicValue or() => packed.or();

  @override
  LogicValue xor() => packed.xor();

  @override
  bool get isZero => packed.isZero;

  @override
  LogicValue _shiftRight(int shamt) => packed._shiftRight(shamt);

  @override
  LogicValue _shiftLeft(int shamt) => packed._shiftLeft(shamt);

  @override
  LogicValue _shiftArithmeticRight(int shamt) =>
      packed._shiftArithmeticRight(shamt);

  @override
  BigInt get _bigIntValue => packed._bigIntValue;

  @override
  BigInt get _bigIntInvalid => packed._bigIntInvalid;

  @override
  int get _intValue => packed._intValue;

  @override
  int get _intInvalid => packed._intInvalid;
}

class _NestedValueArray<T> {
  final List<int> dimensions;
  final List<T> values;

  _NestedValueArray(this.dimensions, this.values);
}

_NestedValueArray<T> _parseNestedArray<T>(
  List<Object?> root, {
  required String argumentName,
}) {
  _NestedValueArray<T> parse(List<Object?> values, List<int> path) {
    if (values.isEmpty) {
      return _NestedValueArray<T>(const [0], const []);
    }

    final children = <_NestedValueArray<T>>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value is T) {
        children.add(_NestedValueArray<T>(const [], [value]));
      } else if (value is List) {
        children.add(parse(value.cast<Object?>(), [...path, index]));
      } else {
        throw ArgumentError.value(value, argumentName,
            'Expected $T or a nested List at ${[...path, index]}.');
      }
    }

    final childDimensions = children.first.dimensions;
    if (children.skip(1).any((child) =>
        !_sameValueArrayDimensions(child.dimensions, childDimensions))) {
      throw ArgumentError.value(
          root, argumentName, 'Nested lists must be rectangular.');
    }
    return _NestedValueArray<T>(
      [values.length, ...childDimensions],
      children.expand((child) => child.values).toList(growable: false),
    );
  }

  return parse(root, const []);
}

List<int> _validateValueArrayDimensions(List<int> dimensions) {
  final normalized = List<int>.unmodifiable(dimensions);
  if (normalized.isEmpty) {
    throw ArgumentError.value(dimensions, 'dimensions', 'Must not be empty.');
  }
  if (normalized.any((dimension) => dimension < 0)) {
    throw ArgumentError.value(
        dimensions, 'dimensions', 'Dimensions must be non-negative.');
  }
  return normalized;
}

void _validateValueArrayElementWidth(int elementWidth) {
  if (elementWidth < 0) {
    throw ArgumentError.value(
        elementWidth, 'elementWidth', 'Must be non-negative.');
  }
}

void _validateValueCount(
    List<int> dimensions, int valueCount, String argumentName) {
  final expected = _valueArrayLength(dimensions);
  if (valueCount != expected) {
    throw ArgumentError.value(valueCount, argumentName,
        'Must contain exactly $expected values for shape $dimensions.');
  }
}

void _validateElementWidths(
    Iterable<LogicValue> values, int elementWidth, String argumentName) {
  for (final value in values) {
    if (value.width != elementWidth) {
      throw ArgumentError.value(
          value, argumentName, 'All values must have width $elementWidth.');
    }
  }
}

int _valueArrayLength(List<int> dimensions) =>
    dimensions.fold(1, (length, dimension) => length * dimension);

List<int> _valueArrayIndices(List<int> dimensions, int flatIndex) {
  final indices = List.filled(dimensions.length, 0);
  for (var dimension = dimensions.length - 1; dimension >= 0; dimension--) {
    final size = dimensions[dimension];
    indices[dimension] = size == 0 ? 0 : flatIndex % size;
    flatIndex = size == 0 ? 0 : flatIndex ~/ size;
  }
  return indices;
}

int _valueArrayFlatIndex(List<int> dimensions, List<int> indices) {
  if (indices.length != dimensions.length) {
    throw RangeError.range(
        indices.length, dimensions.length, dimensions.length, 'indices.length');
  }

  var flatIndex = 0;
  for (var dimension = 0; dimension < dimensions.length; dimension++) {
    final index = indices[dimension];
    final size = dimensions[dimension];
    if (index < 0 || index >= size) {
      throw RangeError.range(index, 0, size - 1, 'indices[$dimension]');
    }
    flatIndex = flatIndex * size + index;
  }
  return flatIndex;
}

bool _sameValueArrayDimensions(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

void _checkValueArrayIsTwoDimensional(List<int> dimensions) {
  if (dimensions.length != 2) {
    throw StateError('Expected exactly two dimensions, got $dimensions.');
  }
}
