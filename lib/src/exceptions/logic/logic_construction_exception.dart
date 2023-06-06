// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_construction_exception.dart
// An exception thrown when a logical signal fails to construct.
//
// 2023 June 1
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] is connecting to itself.
class LogicConstructionException extends RohdException {
  /// A message describing why the construction failed.
  final String reason;

  /// Creates an exception when a [Logic] is trying to connect itself.
  LogicConstructionException(this.reason)
      : super('Failed to construct signal: $reason');
}
