// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_does_not_exist_exception.dart
// Definition for exception when a port is not present.
//
// 2023 December 26
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a port has the wrong width.
class PortDoesNotExistException extends RohdException {
  /// Constructs a new [Exception] for when a port is not present.
  PortDoesNotExistException(super.message);
}
