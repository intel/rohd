// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_conversion_exception.dart
// An exception that is thrown when a conversion from a [LogicValue] fails
// (such as to a [String]).
//
// 2024 December 26
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// An exception that is thrown when a [LogicValue] cannot be
/// properly converted.
class LogicValueConversionException extends RohdException {
  /// Creates an exception for when conversion of a `LogicValue` fails.
  LogicValueConversionException(String message)
      : super('Failed to convert `LogicValue`: $message');
}
