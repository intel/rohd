/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// put_exception.dart
/// An exception that thrown when a signal failes to `put`.
///
/// 2023 January 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that thrown when a [Logic] signal fails to `put`.
class PutException extends RohdException {
  /// Creates an exception for when a `put` fails on a `Logic` with [context] as
  /// to where the
  PutException(String context, String message)
      : super('Failed to put value on signal ($context): $message');
}
