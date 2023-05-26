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
  //TODO: calculate dimension
  // Note: if any level of hierarchy has any elemnt *not* an array, then that's the end of it (flatten from that point down)

  //TODO: if there's complex structure below an array, need to convey that it is flattened when instantiated somehow
  // OR: just ban lists of anything other than vanilla logics?  that's probably good enough?

  late final List<int> dimensions = _calculateDimensions();

  //TODO: support ports that are packed, unpacked, or a mix

  List<int> _calculateDimensions() {
    // current dimension is just the length
    final currDim = elements.length;

    if (currDim == 0) {
      return const [0];
    }

    // check if all elements are:
    // - LogicArrays
    // - with the same dimensions
    // - with same element widths

    //TODO: if we always construct ourselves, then this is safer?
    final allElementsAreArray =
        elements.firstWhereOrNull((element) => element is! LogicArray) == null;

    if (!allElementsAreArray) {
      return [currDim];
    }

    final firstDim = (elements.first as LogicArray).dimensions;

    final listEq = const ListEquality<int>().equals;

    for (final element in elements) {
      element as LogicArray;
      if (!listEq(firstDim, element.dimensions)) {
        return [currDim];
      }
    }

    // if they're all the same, return it back up
    return [currDim, ...firstDim];
  }

  late final int elementWidth = _calculateElementWidth();

  int _calculateElementWidth() {
    if (width == 0) {
      return 0;
    }

    // assume all elements are the same width

    Logic arr = this;
    while (arr.elements.first is LogicArray) {
      arr = arr.elements.first;
    }
    return arr.elements.first.width;
  }

  @override
  String toString() => 'LogicArray($dimensions, $elementWidth): $name';

  ///TODO
  LogicArray._(super.elements, {super.name, this.numDimensionsUnpacked = 0}) {
    if (elements.isNotEmpty) {
      final dim0 = elements.first.width;
      for (final component in elements) {
        if (component.width != dim0) {
          throw PortWidthMismatchException(component, dim0,
              additionalMessage:
                  'All elements of a `LogicArray` must be equal width.');
        }
      }
    }
  }

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
      //TODO
      throw Exception('Array must have at least 1 dimension');
    }

    //TODO: check that numDimensionsUnpacked <= dimensions.length

    return LogicArray._(
      List.generate(
          dimensions[0],
          (index) => (dimensions.length == 1
              ? Logic(width: elementWidth)
              : LogicArray(
                  dimensions
                      .getRange(1, dimensions.length)
                      .toList(growable: false),
                  elementWidth,
                  //TODO: test that this gets propagated down properly
                  numDimensionsUnpacked: max(0, numDimensionsUnpacked - 1),
                ))
            ..arrayIndex = index,
          growable: false),
      name: name,
      numDimensionsUnpacked: numDimensionsUnpacked,
    );
  }

  //TODO
  List<int>? get arrayLocationFromRoot {
    if (!isArrayMember) {
      return [];
    }

    return [
      ...parentStructure!.arrayLocationFromRoot!,
      arrayIndex!,
    ];
  }

  //TODO: doc and test
  factory LogicArray.of(Logic other,
          {required List<int> dimensions,
          required int elementWidth,
          String? name,
          int numDimensionsUnpacked = 0}) =>
      LogicArray(dimensions, elementWidth,
          name: name, numDimensionsUnpacked: numDimensionsUnpacked)
        ..gets(other);

  //TODO: can we be stricter about assignments, etc. for arrays, only like-shaped arrays?
}
