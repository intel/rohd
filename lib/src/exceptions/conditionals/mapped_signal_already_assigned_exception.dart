// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mapped_signal_already_assigned_exception.dart
// An exception thrown when SSA attempts to assign multiple times on the same
// signal.
//
// 2023 April 17
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when [Combinational.ssa] is attempting to
/// deduce mappings for signals but fails since a signal would be connected
/// multiple times.
class MappedSignalAlreadyAssignedException extends RohdException {
  /// Creates a [MappedSignalAlreadyAssignedException] for [signalName].
  MappedSignalAlreadyAssignedException(
    String signalName,
  ) : super('Signal "$signalName" has already been assigned by `ssa`,'
            ' but apparently needs to be connected again.'
            ' This is an indication that a remapped signal was incorrectly'
            ' used twice in different contexts.');
}
