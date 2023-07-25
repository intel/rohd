// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_value_operation_exception.dart
// An exception that is thrown when a given operation cannot be performed on
// invalid LogicValue
//
// 2023 June 4
// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when a given operation cannot be performed on
/// invalid [LogicValue]
class InvalidValueOperationException extends RohdException {
  /// An exception that is thrown when a given operation [op] cannot be
  /// performed on invalid input [a] i.e., [LogicValue.isValid] is
  /// `false`.
  InvalidValueOperationException(LogicValue a, String op)
      : super('$op operation cannot be performed on invalid LogicValue $a');
}
