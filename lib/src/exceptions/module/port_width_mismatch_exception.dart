// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_width_mismatch_exception.dart
// Definition for exception when a port has the wrong width.
//
// 2023 April 18
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a port has the wrong width.
class PortWidthMismatchException extends RohdException {
  /// Constructs a new [Exception] for when a port has the wrong width.
  PortWidthMismatchException(Logic port, int expectedWidth,
      {String additionalMessage = ''})
      : super('Port ${port.name} has the wrong width.'
            ' Expected $expectedWidth but found ${port.width}.'
            ' $additionalMessage');

  /// Constructs a new [Exception] for when two ports should have been the
  /// same width, but were not.
  PortWidthMismatchException.equalWidth(Logic port1, Logic port2)
      : super('Expected ports $port1 and $port2 to be the same width,'
            ' but they are not.');
}
