// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unassignable_exception.dart
// An exception that thrown when a signal fails to `put`.
//
// 2024 October 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An exception that thrown when a [Logic] signal fails to `put`.
class UnassignableException extends RohdException {
  /// Creates an exception for when a [Logic] is marked as unassignable but
  /// something tried to assign to it.
  UnassignableException(Logic logic, {String? reason})
      : super([
          'The signal "$logic" has been marked as unassignable.',
          if (reason != null) ' $reason'
        ].join());
}
