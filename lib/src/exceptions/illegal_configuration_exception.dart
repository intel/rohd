// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// illegal_configuration_exception.dart
// An exception thrown when something is configured in an illegal way.
//
// 2023 June 13
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/exceptions/exceptions.dart';

/// An exception that is thrown when somethins is configured in an illegal way.
class IllegalConfigurationException extends RohdException {
  /// Creates a new [IllegalConfigurationException] with a [message] explaining
  /// what was illegal about it.
  IllegalConfigurationException(super.message);
}
