// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Represents a multi-dimensional array structure of independent [Logic]s.
class LogicArray extends LogicStructure {
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

  @override
  final Naming naming;

  @override
  String toString() => 'LogicArray($dimensions, $elementWidth): $name';

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
  factory LogicArray(List<int> dimensions, int elementWidth,
      {String? name, int numUnpackedDimensions = 0, Naming? naming}) {
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
        : UnmodifiableListView(
            dimensions.getRange(1, dimensions.length).toList(growable: false));

    // if the total width will eventually be 0, then force element width to 0
    if (elementWidth != 0 && dimensions.reduce((a, b) => a * b) == 0) {
      elementWidth = 0;
    }

    return LogicArray._(
      List.generate(
          dimensions.first,
          (index) => (dimensions.length == 1
              ? Logic(
                  width: elementWidth,
                  naming: Naming.renameable,
                )
              : LogicArray(
                  nextDimensions!,
                  elementWidth,
                  numUnpackedDimensions: max(0, numUnpackedDimensions - 1),
                  name: '${name}_$index',
                ))
            .._arrayIndex = index,
          growable: false),
      dimensions: UnmodifiableListView(dimensions),
      elementWidth: elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
      name: name,
      naming: naming,
    );
  }

  /// Creates a new [LogicArray] which has the same [dimensions],
  /// [elementWidth], [numUnpackedDimensions] as `this`.
  ///
  /// If no new [name] is specified, then it will also have the same name.
  @override
  LogicArray clone({String? name}) => LogicArray(dimensions, elementWidth,
      numUnpackedDimensions: numUnpackedDimensions, name: name ?? this.name);

  /// Private constructor for the factory [LogicArray] constructor.
  LogicArray._(
    super.elements, {
    required this.dimensions,
    required this.elementWidth,
    required this.numUnpackedDimensions,
    required String? name,
    required Naming? naming,
  })  : naming = Naming.chooseNaming(name, naming),
        super(name: Naming.chooseName(name, naming, nullStarter: 'a'));

  /// Constructs a new [LogicArray] with a more convenient constructor signature
  /// for when many ports in an interface are declared together.  Also performs
  /// some basic checks on the legality of the array as a port of a [Module].
  factory LogicArray.port(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray(dimensions, elementWidth,
        numUnpackedDimensions: numUnpackedDimensions, name: name);
  }

  /// Perform Assign operation on a Logic subset or slice
  ///
  /// Assigns part of this LogicArray with a given [updatedSubset] of type
  /// [List<Logic>]. The update is performed from a given [start] position
  /// to the length of the [updatedSubset].
  ///
  /// Example:
  /// ```
  /// LogicArray sampleLogic;
  /// // Note: updatedSubset.length < (sampleLogic.length - start)
  /// List<Logic> updatedSubset;
  /// // Assign part of sampleLogic as [updatedSubset]
  /// sampleLogic.assignSubset(updatedSubset); // start = 0 by default
  /// // assign updated subset to sampleLogic[10:10+updatedSubset.length]
  /// sampleLogic.assignSubset(updatedSubset, 10);
  /// ```
  ///
  void assignSubset(List<Logic> updatedSubset, {int start = 0}) {
    if (updatedSubset.length > elements.length - start) {
      throw LogicConstructionException('${updatedSubset.length}');
    }

    // Assign Logic array from `start` index to `start+updatedSubset.length`
    for (var i = 0; i < updatedSubset.length; i++) {
      elements[start + i] <= updatedSubset[i];
    }
  }
}
