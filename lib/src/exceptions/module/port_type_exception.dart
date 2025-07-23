// Copyright (C) 2024-2025 Intel Corporation
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
      : this.forIntendedName(port.name, additionalMessage);

  /// Constructs a new [Exception] for when a port with the [intendedName] has
  /// the wrong type.
  ///
  /// This constructor is in case the port didn't even get the right name.
  PortTypeException.forIntendedName(String intendedName,
      [String additionalMessage = ''])
      : super('Port $intendedName has an incompatible type.'
            ' $additionalMessage');
}
