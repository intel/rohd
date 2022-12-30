/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_reserved_name_exception.dart
/// An exception that thrown when a reserved name is invalid.
///
/// 2022 October 25
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a reserved name is invalid.
class InvalidReservedNameException extends RohdException {
  /// Display error [message] on invalid reserved name.
  ///
  /// Creates a [InvalidReservedNameException] with an optional error [message].
  InvalidReservedNameException(
      [super.message = 'Reserved Name need to follow proper naming '
          'convention if reserved'
          ' name set to true']);
}
