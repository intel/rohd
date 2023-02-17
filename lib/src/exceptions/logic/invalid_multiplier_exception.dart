/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_multiplier_exception.dart
/// An exception that thrown when a signal has an invalid width.
///
/// 2023 January 24
/// Author: Akshay Wankhede <akshay.wankhede@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] is replicated with an invalid (<1)
/// multiplier.
class InvalidMultiplierException extends RohdException {
  /// Creates an exception when a logic input/output is replicated with an
  /// invalid multiplier
  InvalidMultiplierException(int multiplier)
      : super('A multiplier can not be 0 or negative: $multiplier');
}
