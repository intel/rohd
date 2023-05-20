/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_connection_exception.dart
/// An exception that thrown when there is an invalid logic connection
///
/// 2023 May 20
/// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] is trying for an invalid connection.
class InvalidConnectionException extends RohdException {
  /// Creates an exception when a logic is trying for an invalid connect.
  InvalidConnectionException(Logic a, Logic b)
      : super('Signal "$a" trying to connect with signal "$b"'
            ' is not allowed.');
}
