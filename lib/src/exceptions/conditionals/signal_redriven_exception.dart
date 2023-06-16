/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// signal_redriven_exception.dart
/// An exception that thrown when a signal is
/// redriven multiple times.
///
/// 2022 November 9
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when a [Logic] signal is
/// driven multiple times.
class SignalRedrivenException extends RohdException {
  /// Displays [signals] that are driven multiple times
  /// with default error [message].
  ///
  /// Creates a [SignalRedrivenException] with an optional error [message].
  SignalRedrivenException(Iterable<Logic> signals,
      [String message = 'Sequential drove the same signal(s) multiple times: '])
      : super(message + signals.toString());
}
