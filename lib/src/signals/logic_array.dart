// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array.dart
// Definition of an array of `Logic`s.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/module/module_exceptions.dart';

class LogicArray extends LogicStructure {
  //TODO: calculate dimension
  // Note: if any level of hierarchy has any elemnt *not* an array, then that's the end of it (flatten from that point down)

  ///TODO
  LogicArray(super.components) {
    if (components.isNotEmpty) {
      final dim0 = components.first.width;
      for (final component in components) {
        if (component.width != dim0) {
          throw PortWidthMismatchException(component, dim0,
              additionalMessage:
                  'All elements of a `LogicArray` must be equal width.');
        }
      }
    }
  }

  //TODO: can we be stricter about assignments, etc. for arrays, only like-shaped arrays?
}
