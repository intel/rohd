// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_random_logic_value_exception.dart
// An exception that is thrown when LogicValue generated from Random
// LogicValue is incorrect.
//
// 2023 May 31
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:math';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when the generation of the random [LogicValue]
/// from [Random] results in errors or bugs.
class InvalidRandomLogicValueException extends RohdException {
  /// Creates an exception when the [LogicValue]'s bits generated from [Random]
  /// is incorrect.
  InvalidRandomLogicValueException(String message)
      : super('Generation of the random value is incorrect or errors '
            'due to $message');
}
