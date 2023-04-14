// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// write_after_read_exception.dart
// An exception thrown when a "write after read" violation occurs.
//
// 2023 April 13
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when a "write after read" violation occurs.
///
/// This is also sometimes called a "read before write" violation.
class WriteAfterReadException extends RohdException {
  /// Creates a [WriteAfterReadException] for [signalName].
  WriteAfterReadException(
    String signalName,
  ) : super('Signal "$signalName" changed its value after being used'
            ' within one `Combinational` execution.'
            ' This can lead to a mismatch between simulation and synthesis.'
            ' You may be able to use `Combinational.ssa` to correct your'
            ' design with minimal refactoring.');
}
