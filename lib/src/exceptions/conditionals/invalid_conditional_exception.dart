// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_conditional_exception.dart
// An exception thrown when a conditional is built in an invalid way.
//
// 2023 June 13
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An exception that is thrown when a [Conditional] has been constructed in
/// an invalid way.
class InvalidConditionalException extends RohdException {
  /// Creates a new [InvalidConditionalException] with a [message] explaining
  /// why the conditional was invalid.
  InvalidConditionalException(super.message);
}
