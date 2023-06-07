/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// self_connecting_logic_exception.dart
/// An exception that is thrown when there is a logical signal connecting to
/// itself.
///
/// 2023 May 27
/// Author: Sanchit Kumar <sanchit.dabgotra@gmail.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] is connecting to itself.
class SelfConnectingLogicException extends RohdException {
  /// Creates an exception when a [Logic] is trying to connect itself.
  SelfConnectingLogicException(Logic a, Logic b)
      : super('Failed to connect signal "$a" with signal "$b":'
            ' Self connecting logic not allowed.');
}
