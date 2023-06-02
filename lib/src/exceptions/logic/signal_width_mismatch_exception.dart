// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_width_mismatch_exception.dart
// Definition for exception when a signal has the wrong width.
//
// 2023 June 2
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An [Exception] thrown when a signal has the wrong width.
class SignalWidthMismatchException extends RohdException {
  /// Constructs a new [Exception] for when a signal has the wrong width.
  SignalWidthMismatchException(Logic signal, int expectedWidth,
      {String additionalMessage = ''})
      : super('Signal ${signal.name} has the wrong width.'
            ' Expected $expectedWidth but found ${signal.width}.'
            ' $additionalMessage');
}
