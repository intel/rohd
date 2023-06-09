// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_name_exception.dart
// Definition for an exception thrown when an interface has a naming issue.
//
// 2023 June 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An [Exception] thrown when an interface has an invalid name.
class InterfaceNameException extends RohdException {
  /// Constructs a new [Exception] for when an interface has an invalid name.
  InterfaceNameException(String name, String reason)
      : super('Interface name "$name" is invalid: $reason');
}
