// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Shared private implementation for multidimensional logic arrays.
class _BaseLogicArray extends LogicStructure {
  /// The number of elements at each level of the array, starting from the most
  /// significant outermost level.
  ///
  /// For example `[3, 2]` would indicate a 2-dimensional array, where it is
  /// an array with 3 arrays, each containing 2 arrays.
  final List<int> dimensions;

  /// The width of leaf elements in this array.
  ///
  /// If the array has no leaf elements and/or the [width] is 0, then the
  /// [elementWidth] is always 0.
  final int elementWidth;

  /// Elements at the leaf dimension of this array.
  ///
  /// Unlike [LogicStructure.leafElements], traversal stops at the configured
  /// array leaf. This distinction matters when an array leaf is itself a
  /// [LogicStructure], such as a typed floating-point value.
  late final List<Logic> _arrayElements =
      UnmodifiableListView(_calculateArrayElements());

  /// Elements reached after traversing exactly [dimensions] array levels.
  List<Logic> get arrayElements => _arrayElements;

  @override
  final Naming naming;

  @override
  String toString() => [
        'LogicArray($dimensions, $elementWidth): $name',
        if (isArrayMember) 'index $arrayIndex of ($parentStructure)',
        if (isNet) '[Net]'
      ].join(', ');

  /// The number of [dimensions] which should be treated as "unpacked", starting
  /// from the outermost (first) elements of [dimensions].
  ///
  /// This has no functional impact on simulation or behavior.  It is only used
  /// as a hint for [Synthesizer]s.
  final int numUnpackedDimensions;

  /// Creates an array with specified [dimensions] and [elementWidth] named
  /// [name].
  ///
  /// Setting the [numUnpackedDimensions] gives a hint to [Synthesizer]s about
  /// the intent for declaration of signals. By default, all dimensions are
  /// packed, but if the value is set to more than `0`, then the outer-most
  /// dimensions (first in [dimensions]) will become unpacked.  It must be less
  /// than or equal to the length of [dimensions]. Modifying it will have no
  /// impact on simulation functionality or behavior. In SystemVerilog, there
  /// are some differences in access patterns for packed vs. unpacked arrays.
  factory _BaseLogicArray(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      _BaseLogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: Logic.new,
          logicArrayBuilder: _BaseLogicArray.new,
          arrayBuilder: _BaseLogicArray._,
          isNet: false);

  @override
  final bool isNet;

  /// Creates an array of [LogicNet]s with specified [dimensions] and
  /// [elementWidth] named [name].
  ///
  /// Setting the [numUnpackedDimensions] gives a hint to [Synthesizer]s about
  /// the intent for declaration of signals. By default, all dimensions are
  /// packed, but if the value is set to more than `0`, then the outer-most
  /// dimensions (first in [dimensions]) will become unpacked.  It must be less
  /// than or equal to the length of [dimensions]. Modifying it will have no
  /// impact on simulation functionality or behavior. In SystemVerilog, there
  /// are some differences in access patterns for packed vs. unpacked arrays.
  factory _BaseLogicArray.net(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      _BaseLogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: LogicNet.new,
          logicArrayBuilder: _BaseLogicArray.net,
          arrayBuilder: _BaseLogicArray._,
          isNet: true);

  /// Creates an array from pre-built [elements].
  ///
  /// This constructor supports subclasses whose leaf dimension contains a
  /// specialized [Logic] or [LogicStructure]. For arrays with more than one
  /// dimension, [elements] must be arrays matching the remaining
  /// dimensions. For a one-dimensional array, each element must have
  /// [elementWidth] bits.
  @protected
  _BaseLogicArray.structured(List<Logic> elements,
      {required List<int> dimensions,
      required this.elementWidth,
      String? name,
      this.numUnpackedDimensions = 0,
      Naming? naming,
      bool? isNet})
      : dimensions = List<int>.unmodifiable(dimensions),
        isNet = isNet ?? elements.every((element) => element.isNet),
        naming = Naming.chooseNaming(name, naming),
        super(elements,
            name: Naming.chooseName(name, naming, nullStarter: 'a')) {
    if (dimensions.isEmpty) {
      throw LogicConstructionException(
          'Arrays must have at least 1 dimension.');
    }
    if (dimensions.any((dimension) => dimension < 0)) {
      throw LogicConstructionException(
          'Array dimensions must be non-negative.');
    }
    if (numUnpackedDimensions > dimensions.length) {
      throw LogicConstructionException(
          'Cannot unpack more than all of the dimensions.');
    }
    if (elements.length != dimensions.first) {
      throw LogicConstructionException(
          'Array elements must match the first dimension.');
    }

    if (dimensions.length == 1) {
      if (elements.any((element) => element.width != elementWidth)) {
        throw LogicConstructionException(
            'Array leaves must match elementWidth.');
      }
    } else {
      final childDimensions = dimensions.sublist(1);
      if (elements.any((element) =>
          element is! _BaseLogicArray ||
          !_sameDimensions(element.dimensions, childDimensions) ||
          element.elementWidth != elementWidth)) {
        throw LogicConstructionException(
            'Child arrays must match the remaining dimensions and width.');
      }
    }

    for (final (index, element) in elements.indexed) {
      element._arrayIndex = index;
    }
  }

  /// Internal factory constructor.
  ///
  /// Creates an array with specified [dimensions] and [elementWidth] named
  /// [name].
  ///
  /// Setting the [numUnpackedDimensions] gives a hint to [Synthesizer]s about
  /// the intent for declaration of signals. By default, all dimensions are
  /// packed, but if the value is set to more than `0`, then the outer-most
  /// dimensions (first in [dimensions]) will become unpacked.  It must be less
  /// than or equal to the length of [dimensions]. Modifying it will have no
  /// impact on simulation functionality or behavior. In SystemVerilog, there
  /// are some differences in access patterns for packed vs. unpacked arrays.
  ///
  /// The [logicBuilder] and [logicArrayBuilder] functions should generate
  /// proper types of [Logic]s as elements for the array.
  factory _BaseLogicArray._factory(List<int> dimensions, int elementWidth,
      {required String? name,
      required int numUnpackedDimensions,
      required Naming? naming,
      required bool isNet,
      required Logic Function({int width, Naming naming, String name})
          logicBuilder,
      required _BaseLogicArray Function(List<int> nextDimensions, int width,
              {int numUnpackedDimensions, String name})
          logicArrayBuilder,
      required _BaseLogicArray Function(List<Logic> elements,
              {required List<int> dimensions,
              required int elementWidth,
              required int numUnpackedDimensions,
              required String name,
              required Naming naming,
              required bool isNet})
          arrayBuilder}) {
    if (dimensions.isEmpty) {
      throw LogicConstructionException(
          'Arrays must have at least 1 dimension.');
    }

    if (numUnpackedDimensions > dimensions.length) {
      throw LogicConstructionException(
          'Cannot unpack more than all of the dimensions.');
    }

    // calculate the next layer's dimensions
    final nextDimensions = dimensions.length == 1
        ? null
        : List<int>.unmodifiable(dimensions.getRange(1, dimensions.length));

    // if the total width will eventually be 0, then force element width to 0
    if (elementWidth != 0 && dimensions.reduce((a, b) => a * b) == 0) {
      elementWidth = 0;
    }

    // choose name and naming before creating (and naming) elements
    final newNaming = Naming.chooseNaming(name, naming);
    final newName = Naming.chooseName(name, naming, nullStarter: 'a');
    naming = newNaming;
    name = newName;

    final elements = List.generate(
        dimensions.first,
        (index) => (dimensions.length == 1
            ? logicBuilder(
                width: elementWidth,
                naming: Naming.renameable,
                name: '${name}_$index')
            : logicArrayBuilder(nextDimensions!, elementWidth,
                numUnpackedDimensions: max(0, numUnpackedDimensions - 1),
                name: '${name}_$index'))
          .._arrayIndex = index,
        growable: false);

    return arrayBuilder(elements,
        dimensions: List<int>.unmodifiable(dimensions),
        elementWidth: elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        name: name,
        naming: naming,
        isNet: isNet);
  }

  @override
  _BaseLogicArray _clone({String? name, Naming? naming}) =>
      _BaseLogicArray._factory(dimensions, elementWidth,
          name: name ?? this.name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: this.naming,
              newNaming: naming),
          logicBuilder: isNet ? LogicNet.new : Logic.new,
          logicArrayBuilder: isNet ? _BaseLogicArray.net : _BaseLogicArray.new,
          arrayBuilder: _BaseLogicArray._,
          isNet: isNet);

  /// Creates a new array which has the same [dimensions],
  /// [elementWidth], [numUnpackedDimensions], and [isNet] as `this`.
  ///
  /// If no new [name] is specified, then it will also have the same name.
  ///
  /// It is expected that any implementation will override this in a way that
  /// returns the same type as itself.
  @override
  @mustBeOverridden
  _BaseLogicArray clone({String? name}) => _clone(name: name);

  /// Makes a [clone] with the provided [name] and optionally [naming], then
  /// assigns it to be driven by `this`.
  ///
  /// This is a useful utility for naming the result of some hardware
  /// construction without separately declaring a new named signal and then
  /// assigning.
  @override
  _BaseLogicArray named(String name, {Naming? naming}) =>
      _clone(name: name, naming: naming)..gets(this);

  /// Private constructor for the factory [_BaseLogicArray] constructor.
  ///
  /// The [name] and [naming] should have been identified before calling this.
  _BaseLogicArray._(super.elements,
      {required this.dimensions,
      required this.elementWidth,
      required this.numUnpackedDimensions,
      required String super.name,
      required this.naming,
      required this.isNet});

  List<Logic> _calculateArrayElements() => dimensions.length == 1
      ? elements
      : elements
          .cast<_BaseLogicArray>()
          .expand((element) => element.arrayElements)
          .toList(growable: false);
}

/// A multi-dimensional array structure of independent [Logic]s.
///
/// This is the ordinary [Logic]-leaf specialization of [LogicArrayOf]. It has
/// the same construction, port, clone, and naming API as the historical
/// `LogicArray` type.
class LogicArray extends LogicArrayOf<Logic> {
  /// Creates an array with specified [dimensions] and [elementWidth] named
  /// [name].
  ///
  /// [numUnpackedDimensions] is a [Synthesizer] hint. When it is greater than
  /// zero, that many outermost dimensions are emitted as unpacked dimensions
  /// in SystemVerilog. It has no effect on simulation behavior.
  factory LogicArray(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: Logic.new,
          logicArrayBuilder: LogicArray.new,
          isNet: false);

  /// Creates an array of [LogicNet]s with [dimensions] and [elementWidth]
  /// named [name].
  ///
  /// [numUnpackedDimensions] has the same synthesis-only meaning as in
  /// [LogicArray].
  factory LogicArray.net(List<int> dimensions, int elementWidth,
          {String? name, int numUnpackedDimensions = 0, Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: LogicNet.new,
          logicArrayBuilder: LogicArray.net,
          isNet: true);

  LogicArray._(List<Logic> elements,
      {required super.dimensions,
      required super.elementWidth,
      required super.numUnpackedDimensions,
      required super.name,
      required super.naming,
      required bool isNet})
      : super.structured(
          elements,
          ({name}) => isNet
              ? LogicNet(name: name, width: elementWidth)
              : Logic(name: name, width: elementWidth),
          isNet: isNet,
        );

  factory LogicArray._factory(List<int> dimensions, int elementWidth,
          {required String? name,
          required int numUnpackedDimensions,
          required Naming? naming,
          required bool isNet,
          required Logic Function({int width, Naming naming, String name})
              logicBuilder,
          required LogicArray Function(List<int> nextDimensions, int width,
                  {int numUnpackedDimensions, String name})
              logicArrayBuilder}) =>
      _BaseLogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: naming,
          logicBuilder: logicBuilder,
          logicArrayBuilder: logicArrayBuilder,
          arrayBuilder: LogicArray._,
          isNet: isNet) as LogicArray;

  @override

  /// Creates a [LogicArray] with the same dimensions, element width, unpacked
  /// dimensions, net type, and name as this array unless [name] is provided.
  LogicArray clone({String? name}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name ?? this.name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: naming,
              newNaming: null),
          logicBuilder: isNet ? LogicNet.new : Logic.new,
          logicArrayBuilder: isNet ? LogicArray.net : LogicArray.new,
          isNet: isNet);

  @override

  /// Clones this array with [name] and connects the clone to this array.
  LogicArray named(String name, {Naming? naming}) =>
      LogicArray._factory(dimensions, elementWidth,
          name: name,
          numUnpackedDimensions: numUnpackedDimensions,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: this.naming,
              newNaming: naming),
          logicBuilder: isNet ? LogicNet.new : Logic.new,
          logicArrayBuilder: isNet ? LogicArray.net : LogicArray.new,
          isNet: isNet)
        ..gets(this);

  @override
  LogicArray getsEach(Iterable<Logic> sources) {
    super.getsEach(sources);
    return this;
  }

  @override
  LogicArray getsGenerated(Logic Function(List<int> indices) generator) {
    super.getsGenerated(generator);
    return this;
  }

  @override
  LogicArray reshape(List<int> newDimensions, {String? name}) {
    if (_arrayLength(newDimensions) != arrayElements.length) {
      throw ArgumentError.value(newDimensions, 'newDimensions',
          'Must contain ${arrayElements.length} array elements.');
    }
    return (isNet ? LogicArray.net : LogicArray.new)(
      newDimensions,
      elementWidth,
      name: name,
      numUnpackedDimensions: min(numUnpackedDimensions, newDimensions.length),
    )..getsEach(arrayElements);
  }

  @override
  LogicArray transpose2D({String? name}) {
    _checkArrayIsTwoDimensional(dimensions);
    return (isNet ? LogicArray.net : LogicArray.new)(
      [dimensions[1], dimensions[0]],
      elementWidth,
      name: name,
      numUnpackedDimensions: numUnpackedDimensions,
    )..getsGenerated((indices) => at([indices[1], indices[0]]));
  }

  @override
  Iterable<LogicArray> get majorSlices {
    if (dimensions.length < 2) {
      throw StateError('majorSlices requires at least two dimensions.');
    }
    return elements.cast<LogicArray>();
  }

  /// Creates an array port with a convenient constructor signature.
  ///
  /// The port uses mergeable naming so repeated interface connections retain a
  /// single SystemVerilog port declaration.
  factory LogicArray.port(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        name: name,
        naming: Naming.mergeable);
  }

  /// Creates a net array port with a convenient constructor signature.
  ///
  /// The port uses mergeable naming so repeated interface connections retain a
  /// single SystemVerilog port declaration.
  factory LogicArray.netPort(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray.net(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions,
        name: name,
        naming: Naming.mergeable);
  }
}

bool _sameDimensions(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);
