// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_logicvalue_exception.dart
// An exception that is thrown when an invalid [LogicValue] is found for
// operation.
//
// 2023 June 4
// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when an invalid [LogicValue] is found for
/// operation.
class InvalidLogicValueException extends RohdException {
  /// An exception that is thrown when an invalid `LogicValue` [a] of `x` or `z`
  /// is found for the operation.
  InvalidLogicValueException(LogicValue a)
      : super('Found Invalid Logical Value $a');
}
