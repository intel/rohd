// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_type_exception.dart
// Definition for exception when a port has the wrong type.
//
// 2024 May 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a port has the wrong type.
class PortTypeException extends RohdException {
  /// Constructs a new [Exception] for when a port has the wrong type.
  PortTypeException(Logic port, [String additionalMessage = ''])
      : super('Port ${port.name} has the wrong type.'
            ' $additionalMessage');
}
