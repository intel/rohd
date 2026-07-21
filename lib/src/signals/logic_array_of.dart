// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array_of.dart
// Definition of typed logic arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'signals.dart';

/// Builds one leaf element of a [LogicArrayOf].
typedef LogicArrayElementBuilder<T extends Logic> = T Function({String? name});

/// A multidimensional logic array with leaves of type [T].
///
/// Intermediate dimensions are [LogicArray]s, while the configured array leaf
/// can be any [Logic], including a [LogicStructure] such as a floating-point
/// signal. Packed conversion happens only at that leaf boundary.
class LogicArrayOf<T extends Logic> extends LogicArray {
  /// Labels used to name elements at each dimension.
  final List<String> dimensionNames;

  final LogicArrayElementBuilder<T> _elementBuilder;

  late final List<T> _typedLeafElements = List<T>.unmodifiable(
    arrayElements.cast<T>(),
  );

  /// Creates an array with [dimensions] and typed leaves from [elementBuilder].
  LogicArrayOf(
    List<int> dimensions,
    LogicArrayElementBuilder<T> elementBuilder, {
    List<String>? dimensionNames,
    String? name,
  }) : this._(
            _LogicArrayOfBuild.build(dimensions, elementBuilder,
                dimensionNames: dimensionNames),
            elementBuilder,
            name: name);

  LogicArrayOf._(
    _LogicArrayOfBuild<T> build,
    this._elementBuilder, {
    String? name,
  })  : dimensionNames = build.dimensionNames,
        super.structured(build.elements,
            dimensions: build.dimensions,
            elementWidth: build.elementWidth,
            name: name);

  /// Typed leaves in row-major order.
  List<T> get typedLeafElements => UnmodifiableListView<T>(_typedLeafElements);

  /// Typed leaves paired with their multidimensional indices.
  Iterable<(List<int>, T)> get indexedElements =>
      indexedLeaves.map((entry) => (entry.$1, entry.$2 as T));

  /// Returns the typed leaf at multidimensional [indices].
  T elementAt(List<int> indices) => at(indices) as T;

  /// Current packed leaves in the value domain.
  LogicValueArray get logicValues => LogicValueArray.fromLogicArray(this);

  /// Decodes current packed leaves into semantic values using [codec].
  LogicValueArrayOf<U> valueArrayOf<U>(LogicValueCodec<U> codec) =>
      LogicValueArrayOf.fromLogicValues(logicValues, codec: codec);

  /// Drives typed leaves from [values].
  void putLogicValues(LogicValueArray values) => values.putInto(this);

  /// Drives typed logic leaves from semantic [values].
  void putValueArrayOf<U>(LogicValueArrayOf<U> values) =>
      putLogicValues(values.logicValues);

  /// Packs typed leaves into a conventional [LogicArray].
  LogicArray toLogicArray({String? name}) =>
      LogicArray(dimensions, elementWidth, name: name)
        ..getsEach(_typedLeafElements.map((element) => element.packed));

  /// Drives typed leaves from a packed [LogicArray].
  void getsPackedValues(LogicArray packedValues) {
    _validateShape(packedValues.dimensions, packedValues.elementWidth);
    for (final (target, source)
        in _typedLeafElements.zipExact(packedValues.arrayElements)) {
      target <= source;
    }
  }

  void _validateShape(List<int> dimensions, int elementWidth) {
    if (!_sameDimensions(this.dimensions, dimensions) ||
        this.elementWidth != elementWidth) {
      throw LogicConstructionException(
          'Values must have dimensions ${this.dimensions} and '
          'elementWidth ${this.elementWidth}.');
    }
  }

  @override
  LogicArrayOf<T> clone({String? name}) =>
      LogicArrayOf(dimensions, _elementBuilder,
          dimensionNames: dimensionNames, name: name ?? this.name);

  @override
  LogicArrayOf<T> named(String name, {Naming? naming}) =>
      clone(name: name)..gets(this);
}

class _LogicArrayOfBuild<T extends Logic> {
  final List<int> dimensions;
  final List<String> dimensionNames;
  final List<Logic> elements;
  final int elementWidth;

  _LogicArrayOfBuild._(
      this.dimensions, this.dimensionNames, this.elements, this.elementWidth);

  factory _LogicArrayOfBuild.build(
      List<int> dimensions, LogicArrayElementBuilder<T> elementBuilder,
      {List<String>? dimensionNames}) {
    final normalizedDimensions = List<int>.unmodifiable(dimensions);
    if (normalizedDimensions.isEmpty ||
        normalizedDimensions.any((dimension) => dimension <= 0)) {
      throw LogicConstructionException(
          'LogicArrayOf dimensions must all be positive.');
    }

    final normalizedNames = List<String>.unmodifiable(
      dimensionNames ??
          Iterable.generate(
              normalizedDimensions.length, (dimension) => 'd${dimension}_'),
    );
    if (normalizedNames.length != normalizedDimensions.length) {
      throw LogicConstructionException(
          'dimensionNames must match the number of dimensions.');
    }

    final elements = List<Logic>.generate(normalizedDimensions.first, (index) {
      final elementName = '${normalizedNames.first}$index';
      return normalizedDimensions.length == 1
          ? elementBuilder(name: elementName)
          : LogicArrayOf<T>(normalizedDimensions.sublist(1), elementBuilder,
              dimensionNames: normalizedNames.sublist(1), name: elementName);
    }, growable: false);
    final typedLeaves = normalizedDimensions.length == 1
        ? elements.cast<T>().toList(growable: false)
        : elements
            .cast<LogicArrayOf<T>>()
            .expand((element) => element.typedLeafElements)
            .toList(growable: false);
    return _LogicArrayOfBuild._(normalizedDimensions, normalizedNames, elements,
        _validateElementWidths(typedLeaves));
  }

  static int _validateElementWidths<T extends Logic>(List<T> elements) {
    final width = elements.first.width;
    if (elements.any((element) => element.width != width)) {
      throw LogicConstructionException(
          'All LogicArrayOf leaves must have the same width.');
    }
    return width;
  }
}
