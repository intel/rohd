// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// put_exception.dart
// An exception that thrown when a signal fails to `put`.
//
// 2023 January 5
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An exception that thrown when a [Logic] signal fails to [Logic.put].
class PutException extends RohdException {
  /// Creates an exception for when a [Logic.put] fails on a [Logic] with
  /// [context] as to where the failure occurred and [message] describing the
  /// failure.
  PutException(String context, String message)
      : super('Failed to put value on signal ($context): $message');
}
