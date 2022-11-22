/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// signal_redriven_exception.dart
/// An exception that is thrown when a signal is
/// redriven multiple times.
///
/// 2022 November 9
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/rohd.dart';

/// Throws [SignalRedrivenException] whenever a [Logic] signal
/// is redriven for mutiple times in [Conditional].
class SignalRedrivenException implements Exception {
  late final String _message;

  /// constructor for SignalRedrivenException,
  /// pass custom String [message] to the constructor to override
  SignalRedrivenException(String signals,
      [String message = 'Sequential drove the same signal(s) multiple times: '])
      : _message = message + signals;

  @override
  String toString() => _message;
}
