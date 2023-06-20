// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// value_width_mismatch_exception.dart
// An exception that is thrown when LogicValue of different width are found.
//
// 2023 June 4
// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when [LogicValue]s of different width are found.
class ValueWidthMismatchException extends RohdException {
  /// Creates an exception when two [LogicValue] considered for the operation
  /// are of different width.
  ValueWidthMismatchException(LogicValue a, LogicValue b)
      : super('Width Mismatch ${a.width} & ${b.width}: '
            'LogicValue must be of same width');
}
