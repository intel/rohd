// Copyright (C) 2022-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_reserved_name_exception.dart
// An exception that thrown when a reserved name is invalid.
//
// 2022 October 25
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a reserved name is invalid.
class InvalidReservedNameException extends RohdException {
  /// An exception with an error [message] for an invalid reserved name.
  ///
  /// Creates a [InvalidReservedNameException] with an optional error [message].
  InvalidReservedNameException(String name)
      : super('The name "$name" was reserved but does not follow'
            ' safe naming conventions. '
            'Generally, reserved names should be valid variable identifiers'
            ' in languages such as Dart and SystemVerilog.');
}
