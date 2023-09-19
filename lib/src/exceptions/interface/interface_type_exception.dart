// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_type_exception.dart
// Definition for an exception thrown when an interface has a type issue.
//
// 2023 June 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when an interface has an issue with its type.
class InterfaceTypeException extends RohdException {
  /// Constructs a new [Exception] for when an interface has an issue with its
  /// type.
  InterfaceTypeException(Interface<dynamic> interface, String reason)
      : super('Interface "$interface" cannot be used in this context: $reason');
}
