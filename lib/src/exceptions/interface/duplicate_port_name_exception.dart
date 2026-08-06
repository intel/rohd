// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// duplicate_port_name_exception.dart
// Definition for an exception thrown when a port name is already in use on an
// interface.
//
// 2026 August 5
// Author: Aisha Salimgereyeva <aishasalimg@gmail.com>

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An [Exception] thrown when a port is added to an interface with a name that
/// is already in use by another port on that same interface.
class DuplicatePortNameException extends RohdException {
  /// Constructs a new [Exception] for when a port named [portName] already
  /// exists on the interface it is being added to.
  DuplicatePortNameException(String portName)
      : super('Port named "$portName" already exists on this interface.');
}
