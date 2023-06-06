// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_construction_exception.dart
// An exception that thrown when a signal failes to `put`.
//
// 2023 May 1
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [LogicValue] cannot be properly constructed.
class LogicValueConstructionException extends RohdException {
  /// Creates an exception for when a construction of a `LogicValue` fails.
  LogicValueConstructionException(String message)
      : super('Failed to construct `LogicValue`: $message');
}
