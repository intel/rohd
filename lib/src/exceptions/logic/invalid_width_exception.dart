/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// invalid_width_exception.dart
/// An exception that thrown when a signal has an invalid width.
///
/// 2023 January 24
/// Author: Akshay Wankhede <akshay.wankhede@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] signal fails to `put`.
class InvalidWidthException extends RohdException {
  /// Creates an exception when a logic input/output has an invalid width
  InvalidWidthException(int width)
      : super('Width can not be 0 or negative: $width');
}
