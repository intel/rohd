// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// simulator_exception.dart
// Definition for exception when an error occurs in the simulator.
//
// 2024 June 11
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when an error occurs in the simulator.
class SimulatorException extends RohdException {
  /// Constructs a new [Exception] for when an error occurs in the simulator
  /// with [message] explaining why.
  SimulatorException(super.message);
}
