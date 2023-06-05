/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// width_mismatch_exception.dart
/// An exception that is thrown when LogicalValue of different width are found.
///
/// 2023 June 4
/// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

///An exception that is thrown when [LogicValue]s of different width are found.
class WidthMismatchException extends RohdException {
  ///Creates an exception when two [LogicValue] considered for the operation
  ///are of different width.
  WidthMismatchException(LogicValue a, LogicValue b)
      : super('Found unequal LogicalValue of width ${a.width} & ${b.width}: '
            'LogicaValue must be of equal width');
}
