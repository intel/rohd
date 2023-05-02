// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/module/module_exceptions.dart';

class LogicArray extends LogicStructure {
  //TODO: calculate dimension
  // Note: if any level of hierarchy has any elemnt *not* an array, then that's the end of it (flatten from that point down)

  //TODO: if there's complex structure below an array, need to convey that it is flattened when instantiated somehow
  // OR: just ban lists of anything other than vanilla logics?  that's probably good enough?

  late final List<int> dimensions = _calculateDimensions();

  List<int> _calculateDimensions() {
    // current dimension is just the length
    final currDim = elements.length;

    if (currDim == 0) {
      return [currDim];
    }

    // check if all elements are:
    // - LogicArrays
    // - with the same dimensions

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

  // _CastError (type 'List<Logic>' is not a subtype of type 'List<LogicArray<LogicArray<Logic>>>' in type cast)

  ///TODO
  LogicArray._(super.elements, {super.name}) {
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

  ///TODO
  factory LogicArray(List<int> dimensions, int width) {
    if (dimensions.isEmpty) {
      //TODO
      throw Exception('Array must have at least 1 dimension');
    }

    return LogicArray._(List.generate(
        dimensions[0],
        (index) => dimensions.length == 1
            ? Logic(width: width)
            : LogicArray(
                dimensions
                    .getRange(1, dimensions.length)
                    .toList(growable: false),
                width),
        growable: false));
  }

  //TODO: can we be stricter about assignments, etc. for arrays, only like-shaped arrays?
}
