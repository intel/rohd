/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_portname_exceptions.dart
/// An exception that thrown when a port or interface name is invalid.
///
/// 2023 April 10
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a port or interface name is invalid.
class InvalidPortNameException extends RohdException {
  /// Display error [message] on invalid reserved name.
  ///
  /// Creates a [InvalidPortNameException] with an optional error [message].
  InvalidPortNameException(String name)
      : super(
            'Invalid name "$name", must be legal SystemVerilog and not collide'
            ' with any keywords.');
}
