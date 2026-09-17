// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// base_logic_array.dart
// Definition of the shared base for logic arrays.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Shared structural base for multidimensional logic arrays.
///
/// Arrays are [LogicStructure]s rather than direct subclasses of [Logic]:
/// their signal identity is the hierarchy of child signals, while the
/// inherited [Logic] behavior is provided by [LogicStructure] through its
/// packed representation. This lets arrays participate in ordinary structure
/// traversal and assignment while adding dimensions and array-boundary
/// traversal. Construct [LogicArray] for ordinary logic values or
/// [TypedLogicArray] for hardware elements with an associated semantic value
/// type.
@internal
abstract class BaseLogicArray extends LogicStructure {
  /// The number of elements at each level of the array, starting from the most
  /// significant outermost level.
  ///
  /// For example `[3, 2]` would indicate a 2-dimensional array, where it is
  /// an array with 3 arrays, each containing 2 arrays.
  final List<int> dimensions;

  /// The width of leaf elements in this array.
  ///
  /// An empty [LogicArray] retains its historical zero element width.
  /// An empty [TypedLogicArray] retains the width of its constructed prototype.
  final int elementWidth;

  /// Cached view of the configured array-element boundary.
  late final List<Logic> _arrayElements =
      UnmodifiableListView(_calculateArrayElements());

  /// Elements reached after traversing exactly [dimensions] array levels.
  ///
  /// Unlike [LogicStructure.leafElements], traversal stops at the configured
  /// array leaf. This distinction matters when an array leaf is itself a
  /// [LogicStructure] or another array.
  List<Logic> get arrayElements => _arrayElements;

  @override
  final Naming naming;

  @override
  String toString() => [
        '$runtimeType($dimensions, $elementWidth): $name',
        if (isArrayMember) 'index $arrayIndex of ($parentStructure)',
        if (isNet) '[Net]'
      ].join(', ');

  /// The number of [dimensions] which should be treated as "unpacked", starting
  /// from the outermost (first) elements of [dimensions].
  ///
  /// This has no functional impact on simulation or behavior.  It is only used
  /// as a hint for [Synthesizer]s.
  final int numUnpackedDimensions;

  @override
  final bool isNet;

  /// Creates an array from pre-built [elements].
  ///
  /// This constructor supports subclasses whose leaf dimension contains a
  /// specialized [Logic] or [LogicStructure]. For arrays with more than one
  /// dimension, [elements] must be arrays matching the remaining
  /// dimensions. For a one-dimensional array, each element must have
  /// [elementWidth] bits.
  @protected
  BaseLogicArray.structured(List<Logic> elements,
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
    if (elementWidth < 0) {
      throw LogicConstructionException(
          'Array element width must be non-negative.');
    }
    if (numUnpackedDimensions < 0 ||
        numUnpackedDimensions > dimensions.length) {
      throw LogicConstructionException(
          'The number of unpacked dimensions must be between 0 and the array '
          'rank.');
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
          element is! BaseLogicArray ||
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

  /// Creates an array with the same shape and element representation.
  @override
  BaseLogicArray clone({String? name});

  /// Creates and connects an array with the requested [name].
  @override
  BaseLogicArray named(String name, {Naming? naming});

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
  factory BaseLogicArray._factory(List<int> dimensions, int elementWidth,
      {required String? name,
      required int numUnpackedDimensions,
      required Naming? naming,
      required bool isNet,
      required Logic Function({int width, Naming naming, String name})
          logicBuilder,
      required BaseLogicArray Function(List<int> nextDimensions, int width,
              {int numUnpackedDimensions, String name})
          logicArrayBuilder,
      required BaseLogicArray Function(List<Logic> elements,
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
    if (dimensions.any((dimension) => dimension < 0)) {
      throw LogicConstructionException(
          'Array dimensions must be non-negative.');
    }
    if (elementWidth < 0) {
      throw LogicConstructionException(
          'Array element width must be non-negative.');
    }
    if (numUnpackedDimensions < 0 ||
        numUnpackedDimensions > dimensions.length) {
      throw LogicConstructionException(
          'The number of unpacked dimensions must be between 0 and the array '
          'rank.');
    }

    final nextDimensions = dimensions.length == 1
        ? null
        : List<int>.unmodifiable(dimensions.getRange(1, dimensions.length));

    if (elementWidth != 0 && dimensions.reduce((a, b) => a * b) == 0) {
      elementWidth = 0;
    }

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

  List<Logic> _calculateArrayElements() => dimensions.length == 1
      ? elements
      : elements
          .cast<BaseLogicArray>()
          .expand((element) => element.arrayElements)
          .toList(growable: false);
}

bool _sameDimensions(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);
