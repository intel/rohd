// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// uninitialized_signal_exception.dart
// An exception thrown when an SSA variable is used before being initialized.
//
// 2023 April 17
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when [Combinational.ssa] detects that an SSA
/// signal is being used before it was initialized.
class UninitializedSignalException extends RohdException {
  /// Creates a [UninitializedSignalException] for [signalName].
  UninitializedSignalException(
    String signalName,
  ) : super('Signal "$signalName" is being used before it has been initialized'
            ' in this `Combinational.ssa`.');
}
