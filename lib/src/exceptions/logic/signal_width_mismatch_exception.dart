// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_width_mismatch_exception.dart
// Definition for exception when a signal has the wrong width.
//
// 2023 June 2
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a signal has the wrong width.
class SignalWidthMismatchException extends RohdException {
  /// Constructs a new [Exception] for when a signal has the wrong width.
  SignalWidthMismatchException(Logic signal, int expectedWidth,
      {String additionalMessage = ''})
      : super('Signal ${signal.name} has the wrong width.'
            ' Expected $expectedWidth but found ${signal.width}.'
            ' $additionalMessage');

  /// Constructs a new [Exception] for when a dynamic has a wrong width.
  SignalWidthMismatchException.forDynamic(
      dynamic val, int expectedWidth, int actualWidth,
      {String additionalMessage = ''})
      : super('Value $val has the wrong width.'
            ' Expected $expectedWidth but found $actualWidth.'
            ' $additionalMessage');

  /// Constructs a new [Exception] for when a dynamic has no width or it could
  /// not be inferred.
  SignalWidthMismatchException.forNull(dynamic val)
      : super('Could not infer width of input $val.'
            ' Please provide a valid width.');

  /// Constructs a new [Exception] for when a dynamic has a wrong width.
  SignalWidthMismatchException.forWidthOverflow(int actualWidth, int maxWidth,
      {String? customMessage})
      : super(customMessage ??
            'Value has the wrong width.'
                ' Expected $actualWidth to be less than or equal to $maxWidth.');
}
