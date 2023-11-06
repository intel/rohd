// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unavailable_reserved_name_exception.dart
// An exception that thrown when a reserved name can't be acquired.
//
// 2023 November 3
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An exception that thrown when a reserved name cannot be acquired.
class UnavailableReservedNameException extends RohdException {
  /// Constructs an error indicating that the reserved [name] could not be
  /// acquired.
  UnavailableReservedNameException(String name)
      : this.withMessage('Unable to acquire reserved name "$name"');

  /// Constructs an error indicating that the reserved `name` could not be
  /// acquired with a [message] explaining why.
  UnavailableReservedNameException.withMessage(super.message);
}
