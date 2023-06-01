// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

part of signals;

class LogicArray extends LogicStructure {
  final List<int> dimensions;

  /// The width of leaf elements in this array.
  ///
  /// If the array has no leaf elements and/or the [width] is 0, then the
  /// [elementWidth] is always 0.
  final int elementWidth;

  @override
  String toString() => 'LogicArray($dimensions, $elementWidth): $name';

  final int numDimensionsUnpacked;

  ///TODO
  ///
  /// Setting the [numDimensionsUnpacked] gives a hint to [Synthesizer]s about
  /// the intent for declaration of signals. By default, all dimensions are
  /// packed, but if the value is set to more than `0`, then the outer-most
  /// dimensions (first in [dimensions]) will become unpacked.  It must be less
  /// than or equal to the length of [dimensions]. Modifying it will have no
  /// impact on simulation functionality or behavior. In SystemVerilog, there
  /// are some differences in access patterns for packed vs. unpacked arrays.
  factory LogicArray(List<int> dimensions, int elementWidth,
      {String? name, int numDimensionsUnpacked = 0}) {
    if (dimensions.isEmpty) {
      throw LogicConstructionException(
          'Arrays must have at least 1 dimension.');
    }

    if (numDimensionsUnpacked > dimensions.length) {
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
              ? Logic(width: elementWidth)
              : LogicArray(
                  nextDimensions!, elementWidth,
                  //TODO: test that this gets propagated down properly
                  numDimensionsUnpacked: max(0, numDimensionsUnpacked - 1),
                  name: '${name}_$index',
                ))
            .._arrayIndex = index,
          growable: false),
      dimensions: UnmodifiableListView(dimensions),
      elementWidth: elementWidth,
      numDimensionsUnpacked: numDimensionsUnpacked,
      name: name,
    );
  }

  ///TODO
  LogicArray._(
    super.elements, {
    required this.dimensions,
    required this.elementWidth,
    required this.numDimensionsUnpacked,
    required super.name,
  });

  factory LogicArray.port(String name,
      [List<int> dimensions = const [1],
      int elementWidth = 1,
      int numDimensionsUnpacked = 0]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicArray(dimensions, elementWidth,
        numDimensionsUnpacked: numDimensionsUnpacked, name: name);
  }
}
