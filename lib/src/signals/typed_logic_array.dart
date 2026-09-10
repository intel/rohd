// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_logic_array.dart
// Definition of typed logic arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'signals.dart';

/// Builds one leaf element of a [TypedLogicArray].
typedef TypedLogicArrayElementBuilder<T extends Logic> = T Function(
    {String? name});

/// Checks whether two typed hardware elements use compatible value formats.
typedef TypedLogicArrayElementCompatibility<T extends Logic> = bool Function(
    T prototype, T element);

/// Selects the canonical packed-value codec when [V] is [LogicValue].
LogicValueCodec<V> _resolveTypedLogicValueCodec<V>(
    LogicValueCodec<V>? valueCodec) {
  if (valueCodec != null) {
    return valueCodec;
  }
  if (V == LogicValue) {
    return LogicValueCodec.logicValue as LogicValueCodec<V>;
  }
  throw ArgumentError.notNull('valueCodec');
}

/// A multidimensional logic array with hardware leaves of type [T] and
/// semantic values of type [V].
///
/// [elements] contains the immediate children of the outermost dimension.
/// [arrayElements] traverses the number of array levels declared by
/// [dimensions] and then stops, returning one [T] for each declared array
/// position. It does not recurse into a [LogicStructure] or nested array stored
/// as a [T].
///
/// For example, a `[2, 3]` array of two-field `Sample` structures has six
/// [arrayElements] and twelve recursive [LogicStructure.leafElements]. A `[2]`
/// array whose [T] is a three-element [LogicArray] has two [arrayElements] and
/// six recursive leaves. An eight-bit [Logic] is one leaf, not eight leaves.
///
/// [value] and [previousValue] preserve [V] through [TypedValueArray]
/// snapshots. Standard [Logic.changed] events remain packed
/// [LogicValueChanged] events.
class TypedLogicArray<T extends Logic, V> extends BaseLogicArray {
  /// Labels used to name elements at each dimension.
  final List<String> dimensionNames;

  /// Recreates one [T] for cloning and shape transformations.
  final TypedLogicArrayElementBuilder<T> _elementBuilder;

  /// Converts each element's packed bits to and from its semantic value type.
  final LogicValueCodec<V> valueCodec;

  /// Additional representation compatibility required between all elements.
  // Safe because it is invoked only on elements produced by [_elementBuilder].
  // ignore: unsafe_variance
  final TypedLogicArrayElementCompatibility<T>? _elementCompatibility;

  /// Unmodifiable typed view of the configured array-element boundary.
  late final List<T> _typedArrayElements =
      List<T>.unmodifiable(super.arrayElements.cast<T>());

  @override
  List<T> get arrayElements => _typedArrayElements;

  /// Creates an array with [dimensions] and typed leaves from [elementBuilder].
  ///
  /// [valueCodec] may be omitted only when [V] is [LogicValue], in which case
  /// the canonical identity codec is used.
  ///
  /// [numUnpackedDimensions] controls how many outer dimensions are emitted as
  /// unpacked dimensions by synthesis.
  TypedLogicArray(
    List<int> dimensions,
    TypedLogicArrayElementBuilder<T> elementBuilder, {
    LogicValueCodec<V>? valueCodec,
    TypedLogicArrayElementCompatibility<T>? elementCompatibility,
    List<String>? dimensionNames,
    String? name,
    Naming? naming,
    int numUnpackedDimensions = 0,
  }) : this._(
            _TypedLogicArrayBuild<T, V>.build(dimensions, elementBuilder,
                _resolveTypedLogicValueCodec(valueCodec), elementCompatibility,
                dimensionNames: dimensionNames,
                numUnpackedDimensions: numUnpackedDimensions),
            elementBuilder,
            _resolveTypedLogicValueCodec(valueCodec),
            elementCompatibility,
            name: name,
            naming: naming,
            numUnpackedDimensions: numUnpackedDimensions);

  // ignore: use_super_parameters - invokes the protected structured constructor.
  TypedLogicArray._(
    _TypedLogicArrayBuild<T, V> build,
    this._elementBuilder,
    this.valueCodec,
    this._elementCompatibility, {
    required int numUnpackedDimensions,
    super.name,
    Naming? naming,
  })  : dimensionNames = build.dimensionNames,
        super.structured(build.elements,
            dimensions: build.dimensions,
            elementWidth: build.elementWidth,
            numUnpackedDimensions: numUnpackedDimensions,
            naming: naming,
            isNet: build.isNet);

  /// Creates a typed array from structurally compatible [elements].
  @protected
  TypedLogicArray.structured(
    super.elements,
    this._elementBuilder, {
    required this.valueCodec,
    required super.dimensions,
    required super.elementWidth,
    required super.numUnpackedDimensions,
    required String name,
    required Naming naming,
    required super.isNet,
    TypedLogicArrayElementCompatibility<T>? elementCompatibility,
    List<String>? dimensionNames,
  })  : _elementCompatibility = elementCompatibility,
        dimensionNames =
            _normalizeLogicArrayDimensionNames(dimensions, dimensionNames),
        super.structured(
          name: name,
          naming: naming,
        );

  /// Array elements paired with their row-major multidimensional indices.
  Iterable<(List<int>, T)> get indexedElements => Iterable.generate(
      arrayElements.length,
      (index) => (_arrayIndices(dimensions, index), arrayElements[index]));

  /// Returns the array element at multidimensional [indices].
  T at(List<int> indices) {
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
    return current as T;
  }

  /// Connects row-major [arrayElements] to [sources].
  TypedLogicArray<T, V> getsEach(Iterable<Logic> sources) {
    for (final (target, source) in _zipExact(arrayElements, sources)) {
      target <= source;
    }
    // ignore: avoid_returning_this - preserves the fluent array receiver type.
    return this;
  }

  /// Connects each array element to a value generated from its indices.
  TypedLogicArray<T, V> getsGenerated(
      Logic Function(List<int> indices) generator) {
    for (final (indices, target) in indexedElements) {
      target <= generator(indices);
    }
    // ignore: avoid_returning_this - preserves the fluent array receiver type.
    return this;
  }

  /// Constructs connected hardware with [newDimensions] in row-major order.
  ///
  /// The returned array contains new elements driven by this array; it is not
  /// an alias or view. [numUnpackedDimensions] is retained when the rank grows
  /// and clamped to the new rank when it shrinks. Dimension names are retained
  /// only when the rank is unchanged.
  TypedLogicArray<T, V> reshape(List<int> newDimensions, {String? name}) {
    if (_arrayLength(newDimensions) != arrayElements.length) {
      throw ArgumentError.value(newDimensions, 'newDimensions',
          'Must contain ${arrayElements.length} array elements.');
    }
    return TypedLogicArray<T, V>(newDimensions, _elementBuilder,
        valueCodec: valueCodec,
        elementCompatibility: _elementCompatibility,
        dimensionNames: newDimensions.length == dimensions.length
            ? dimensionNames
            : _defaultDimensionNames(newDimensions.length),
        name: name,
        numUnpackedDimensions: min(numUnpackedDimensions, newDimensions.length))
      ..getsEach(arrayElements);
  }

  /// Constructs a connected two-dimensional transpose while preserving [T].
  ///
  /// The returned array contains new elements, swaps the dimension names, and
  /// retains [numUnpackedDimensions].
  TypedLogicArray<T, V> transpose2D({String? name}) {
    _checkArrayIsTwoDimensional(dimensions);
    return TypedLogicArray<T, V>(
        [dimensions[1], dimensions[0]], _elementBuilder,
        valueCodec: valueCodec,
        elementCompatibility: _elementCompatibility,
        dimensionNames: [dimensionNames[1], dimensionNames[0]],
        name: name,
        numUnpackedDimensions: numUnpackedDimensions)
      ..getsGenerated((indices) => at([indices[1], indices[0]]));
  }

  /// Immediate typed child arrays along the first dimension.
  Iterable<TypedLogicArray<T, V>> get majorSlices {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }
    return elements.cast<TypedLogicArray<T, V>>();
  }

  /// Flattens all nested array dimensions into one typed array of [U] leaves.
  ///
  /// Each nested array layer must be rectangular: sibling arrays must have the
  /// same dimensions and element width. The returned dimensions concatenate
  /// every nested layer, preserving row-major ordering and index addresses.
  TypedLogicArray<U, UValue> flattenNestedDimensions<U extends Logic, UValue>({
    required LogicValueCodec<UValue> valueCodec,
    TypedLogicArrayElementCompatibility<U>? elementCompatibility,
    String? name,
  }) {
    var leaves = arrayElements.cast<Logic>().toList(growable: false);
    final flattenedDimensions = <int>[...dimensions];
    var flattenedUnpackedDimensions = numUnpackedDimensions;
    TypedLogicArrayElementBuilder<Logic> flattenedElementBuilder =
        _elementBuilder;
    Object discoveredValueCodec = this.valueCodec;
    var prototype = leaves.isEmpty
        ? flattenedElementBuilder(name: 'flatten_prototype')
        : leaves.first;

    while (prototype is TypedLogicArray<Logic, Object?>) {
      if (leaves.isNotEmpty &&
          leaves.any((leaf) => leaf is! TypedLogicArray<Logic, Object?>)) {
        throw LogicConstructionException(
            'Nested array leaves must have a uniform depth.');
      }

      final arrays = leaves.cast<TypedLogicArray<Logic, Object?>>();
      final reference = arrays.isEmpty ? prototype : arrays.first;
      if (arrays.any((array) =>
          !_sameDimensions(array.dimensions, reference.dimensions) ||
          array.elementWidth != reference.elementWidth ||
          array.numUnpackedDimensions != reference.numUnpackedDimensions ||
          !identical(array.valueCodec, reference.valueCodec))) {
        throw LogicConstructionException(
            'Nested array leaves must have matching dimensions, widths, '
            'unpacked dimensions, and value codecs.');
      }
      if (reference.numUnpackedDimensions > 0 &&
          flattenedUnpackedDimensions != flattenedDimensions.length) {
        throw LogicConstructionException(
            'Cannot flatten unpacked inner dimensions after packed outer '
            'dimensions.');
      }

      flattenedDimensions.addAll(reference.dimensions);
      flattenedUnpackedDimensions += reference.numUnpackedDimensions;
      leaves =
          arrays.expand((array) => array.arrayElements).toList(growable: false);
      flattenedElementBuilder = reference._elementBuilder;
      discoveredValueCodec = reference.valueCodec;
      prototype = leaves.isEmpty
          ? flattenedElementBuilder(name: 'flatten_prototype')
          : leaves.first;
    }

    if (prototype is! U || leaves.any((leaf) => leaf is! U)) {
      throw LogicConstructionException(
          'Nested array leaves must have type $U.');
    }

    if (leaves.any((leaf) => leaf.width != prototype.width)) {
      throw LogicConstructionException(
          'Nested array leaves must have matching widths.');
    }
    if (!identical(discoveredValueCodec, valueCodec)) {
      throw LogicConstructionException(
          'valueCodec must be identical to the flattened element codec.');
    }

    var returnPrototype = leaves.isEmpty;
    U buildFlattenedElement({String? name}) {
      final element =
          returnPrototype ? prototype : flattenedElementBuilder(name: name);
      returnPrototype = false;
      if (element is! U) {
        throw LogicConstructionException(
            'Nested array element builder must produce type $U.');
      }
      return element;
    }

    return TypedLogicArray<U, UValue>(
      flattenedDimensions,
      buildFlattenedElement,
      valueCodec: valueCodec,
      elementCompatibility: elementCompatibility,
      name: name,
      numUnpackedDimensions: flattenedUnpackedDimensions,
    )..getsEach(leaves);
  }

  @override
  TypedValueArray<V> get value => TypedValueArray<V>.fromPacked(
        dimensions,
        elementWidth,
        arrayElements.map((element) => element.value),
        codec: valueCodec,
      );

  @override
  TypedValueArray<V>? get previousValue =>
      arrayElements.any((element) => element.previousValue == null)
          ? null
          : TypedValueArray<V>.fromPacked(
              dimensions,
              elementWidth,
              arrayElements.map((element) => element.previousValue!),
              codec: valueCodec,
            );

  /// Packs typed leaves into a conventional [LogicArray].
  LogicArray toLogicArray({String? name}) =>
      (isNet ? LogicArray.net : LogicArray.new)(
        dimensions,
        elementWidth,
        name: name,
        numUnpackedDimensions: numUnpackedDimensions,
      )..getsEach(arrayElements.map((element) => element.packed));

  /// Drives typed leaves from a packed [LogicArray].
  void getsPackedValues(LogicArray packedValues) {
    _validateShape(packedValues.dimensions, packedValues.elementWidth);
    for (final (target, source)
        in _zipExact(arrayElements, packedValues.arrayElements)) {
      target <= source;
    }
  }

  /// Verifies that another array shape can be applied element by element.
  void _validateShape(List<int> dimensions, int elementWidth) {
    if (!_sameDimensions(this.dimensions, dimensions) ||
        this.elementWidth != elementWidth) {
      throw LogicConstructionException(
          'Values must have dimensions ${this.dimensions} and '
          'elementWidth ${this.elementWidth}.');
    }
  }

  /// Creates a clone while allowing subclasses to preserve their runtime type.
  ///
  /// Subclasses with additional metadata should override this method and
  /// reconstruct that metadata together with [dimensions], [dimensionNames],
  /// [elementWidth], [isNet], and [numUnpackedDimensions].
  @protected
  TypedLogicArray<T, V> createClone({
    String? name,
    Naming? naming,
    int? numUnpackedDimensions,
  }) =>
      TypedLogicArray<T, V>(dimensions, _elementBuilder,
          valueCodec: valueCodec,
          elementCompatibility: _elementCompatibility,
          dimensionNames: dimensionNames,
          name: name ?? this.name,
          naming: naming,
          numUnpackedDimensions:
              numUnpackedDimensions ?? this.numUnpackedDimensions);

  @override
  TypedLogicArray<T, V> _clone({String? name, Naming? naming}) => createClone(
        name: name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: this.naming,
          newNaming: naming,
        ),
        numUnpackedDimensions: numUnpackedDimensions,
      );

  @override
  TypedLogicArray<T, V> clone({String? name}) => _clone(name: name);

  @override
  TypedLogicArray<T, V> named(String name, {Naming? naming}) => _clone(
        name: name,
        naming: Naming.chooseCloneNaming(
          originalName: this.name,
          newName: name,
          originalNaming: this.naming,
          newNaming: naming,
        ),
      )..gets(this);
}

/// Validated construction data prepared before initializing [TypedLogicArray].
class _TypedLogicArrayBuild<T extends Logic, V> {
  /// Validated array dimensions.
  final List<int> dimensions;

  /// Validated labels corresponding to [dimensions].
  final List<String> dimensionNames;

  /// Immediate children of the outermost dimension.
  final List<Logic> elements;

  /// Width shared by every typed array element.
  final int elementWidth;

  /// Whether every typed array element is a net.
  final bool isNet;

  /// Stores construction data after all validation is complete.
  _TypedLogicArrayBuild._(this.dimensions, this.dimensionNames, this.elements,
      this.elementWidth, this.isNet);

  /// Builds and validates the complete typed-array hierarchy.
  factory _TypedLogicArrayBuild.build(
      List<int> dimensions,
      TypedLogicArrayElementBuilder<T> elementBuilder,
      LogicValueCodec<V> valueCodec,
      TypedLogicArrayElementCompatibility<T>? elementCompatibility,
      {List<String>? dimensionNames,
      int numUnpackedDimensions = 0,
      T? emptyPrototype,
      bool validateValueCodec = true}) {
    final normalizedDimensions = List<int>.unmodifiable(dimensions);
    if (normalizedDimensions.isEmpty ||
        normalizedDimensions.any((dimension) => dimension < 0)) {
      throw LogicConstructionException(
          'TypedLogicArray dimensions must be non-negative.');
    }
    if (numUnpackedDimensions < 0 ||
        numUnpackedDimensions > normalizedDimensions.length) {
      throw LogicConstructionException(
          'numUnpackedDimensions must be between 0 and the number of '
          'dimensions.');
    }

    final normalizedNames = _normalizeLogicArrayDimensionNames(
        normalizedDimensions, dimensionNames);
    emptyPrototype ??= _arrayLength(normalizedDimensions) == 0
        ? elementBuilder(name: '${normalizedNames.last}prototype')
        : null;

    final elements = List<Logic>.generate(normalizedDimensions.first, (index) {
      final elementName = '${normalizedNames.first}$index';
      return normalizedDimensions.length == 1
          ? elementBuilder(name: elementName)
          : TypedLogicArray<T, V>._(
              _TypedLogicArrayBuild<T, V>.build(
                normalizedDimensions.sublist(1),
                elementBuilder,
                valueCodec,
                elementCompatibility,
                dimensionNames: normalizedNames.sublist(1),
                numUnpackedDimensions: max(0, numUnpackedDimensions - 1),
                emptyPrototype: emptyPrototype,
                validateValueCodec: false,
              ),
              elementBuilder,
              valueCodec,
              elementCompatibility,
              name: elementName,
              numUnpackedDimensions: max(0, numUnpackedDimensions - 1),
            );
    }, growable: false);
    final typedLeaves = normalizedDimensions.length == 1
        ? elements.cast<T>().toList(growable: false)
        : elements
            .cast<TypedLogicArray<T, V>>()
            .expand((element) => element.arrayElements)
            .toList(growable: false);
    if (typedLeaves.any((leaf) =>
        leaf is LogicStructure &&
        leaf is! BaseLogicArray &&
        _containsNestedArray(leaf))) {
      throw LogicConstructionException(
          'TypedLogicArray leaves cannot contain nested typed array fields.');
    }
    if (typedLeaves.any(_containsUnassignableLeaf)) {
      throw LogicConstructionException('TypedLogicArray leaves must be '
          'driveable and cannot contain Consts.');
    }
    final prototype = typedLeaves.isEmpty ? emptyPrototype! : typedLeaves.first;
    if (_containsUnassignableLeaf(prototype)) {
      throw LogicConstructionException('TypedLogicArray leaves must be '
          'driveable and cannot contain Consts.');
    }
    if (prototype is LogicStructure &&
        prototype is! BaseLogicArray &&
        _containsNestedArray(prototype)) {
      throw LogicConstructionException(
          'TypedLogicArray leaves cannot contain nested typed array fields.');
    }
    final prototypeNetComposition = _netComposition(prototype);
    final elementsForNetValidation =
        typedLeaves.isEmpty ? <Logic>[prototype] : typedLeaves;
    if (elementsForNetValidation.any((element) {
      final composition = _netComposition(element);
      return composition.contains(true) && composition.contains(false);
    })) {
      throw LogicConstructionException(
          'TypedLogicArray elements cannot mix net and non-net leaves.');
    }
    if (elementsForNetValidation.any((element) => !_sameNetComposition(
        _netComposition(element), prototypeNetComposition))) {
      throw LogicConstructionException(
          'All TypedLogicArray elements must have matching net composition.');
    }
    if (elementCompatibility != null &&
        elementsForNetValidation
            .cast<T>()
            .any((element) => !elementCompatibility(prototype, element))) {
      throw LogicConstructionException(
          'All TypedLogicArray elements must have compatible value formats.');
    }
    final elementWidth = _validateElementWidths(typedLeaves, prototype.width);
    if (validateValueCodec) {
      _validateValueCodec(prototype.value, elementWidth, valueCodec);
    }
    return _TypedLogicArrayBuild._(
        normalizedDimensions,
        normalizedNames,
        elements,
        elementWidth,
        prototypeNetComposition.every((isNet) => isNet));
  }

  /// Whether [structure] recursively contains an array field.
  static bool _containsNestedArray(LogicStructure structure) =>
      structure.elements.any((element) =>
          element is BaseLogicArray ||
          (element is LogicStructure && _containsNestedArray(element)));

  /// Whether [leaf] is or recursively contains an unassignable constant.
  static bool _containsUnassignableLeaf(Logic leaf) =>
      leaf is Const ||
      (leaf is LogicStructure &&
          leaf.leafElements.any((element) => element is Const));

  /// Net kinds of [element]'s recursive leaves in packed order.
  static List<bool> _netComposition(Logic element) {
    if (element is! LogicStructure) {
      return [element.isNet];
    }
    if (element.leafElements.isNotEmpty) {
      return element.leafElements
          .map((leaf) => leaf.isNet)
          .toList(growable: false);
    }
    return [element is BaseLogicArray && element.isNet];
  }

  /// Whether two recursive net-kind signatures are identical.
  static bool _sameNetComposition(List<bool> left, List<bool> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);

  /// Validates that [elements] all have [expectedWidth].
  static int _validateElementWidths<T extends Logic>(
      List<T> elements, int expectedWidth) {
    if (elements.any((element) => element.width != expectedWidth)) {
      throw LogicConstructionException(
          'All TypedLogicArray leaves must have the same width.');
    }
    return expectedWidth;
  }

  /// Validates four-state decoding and the encoded semantic value width.
  static void _validateValueCodec<V>(
      LogicValue prototype, int elementWidth, LogicValueCodec<V> valueCodec) {
    final encodedPrototype = valueCodec.encode(valueCodec.decode(prototype));
    if (encodedPrototype.width != elementWidth) {
      throw LogicConstructionException(
          'The value codec must encode values with width $elementWidth.');
    }
  }
}

/// Pairs [leftValues] and [rightValues], rejecting unequal lengths.
List<(T, U)> _zipExact<T, U>(Iterable<T> leftValues, Iterable<U> rightValues) {
  final left = leftValues.toList(growable: false);
  final right = rightValues.toList(growable: false);
  if (left.length != right.length) {
    throw StateError('Cannot zip iterables of different lengths.');
  }
  return List.generate(
    left.length,
    (index) => (left[index], right[index]),
    growable: false,
  );
}

/// Returns the number of array positions described by [dimensions].
int _arrayLength(List<int> dimensions) =>
    dimensions.fold(1, (length, dimension) => length * dimension);

/// Converts [flatIndex] to row-major indices for [dimensions].
List<int> _arrayIndices(List<int> dimensions, int flatIndex) {
  final indices = List.filled(dimensions.length, 0);
  for (var dimension = dimensions.length - 1; dimension >= 0; dimension--) {
    final size = dimensions[dimension];
    indices[dimension] = size == 0 ? 0 : flatIndex % size;
    flatIndex = size == 0 ? 0 : flatIndex ~/ size;
  }
  return indices;
}

/// Creates the default element-name prefix for each array dimension.
List<String> _defaultDimensionNames(int rank) =>
    List.generate(rank, (dimension) => 'd${dimension}_', growable: false);

/// Validates and freezes dimension-name prefixes.
List<String> _normalizeLogicArrayDimensionNames(
    List<int> dimensions, List<String>? dimensionNames) {
  final normalized = List<String>.unmodifiable(
    dimensionNames ?? _defaultDimensionNames(dimensions.length),
  );
  if (normalized.length != dimensions.length) {
    throw LogicConstructionException(
        'dimensionNames must match the number of dimensions.');
  }
  if (normalized.any((name) => !Sanitizer.isSanitary(name)) ||
      normalized.toSet().length != normalized.length) {
    throw LogicConstructionException(
        'dimensionNames must be sanitary and unique.');
  }
  return normalized;
}

/// Rejects shapes that cannot be transposed by [TypedLogicArray.transpose2D].
void _checkArrayIsTwoDimensional(List<int> dimensions) {
  if (dimensions.length != 2) {
    throw StateError('Expected exactly two dimensions, got $dimensions.');
  }
}
