// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_truncation_exception.dart
// An exception that is thrown when invalid truncation takes place.
//
// 2023 May 13
// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when a [LogicValue] operation
/// couldn't be performed due invalid data truncation.
class InvalidTruncationException extends RohdException {
  /// Creates an exception when an invalid data truncation occurs
  /// from present type to required type.
  InvalidTruncationException(String message)
      : super("Logical operation couldn't be performed as $message");
}
