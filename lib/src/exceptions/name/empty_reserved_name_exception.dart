/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// empty_reserved_name_exception.dart
/// An exception that thrown when a reserved name is empty string.
///
/// 2023 March 14
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a reserved name is `null`.
class EmptyReservedNameException extends RohdException {
  /// Display error [message] on empty reserved name string.
  ///
  /// Creates a [EmptyReservedNameException] with an optional error [message].
  EmptyReservedNameException(
      [super.message = 'Reserved Name cannot be empty string '
          'if reserved name set to true']);
}
