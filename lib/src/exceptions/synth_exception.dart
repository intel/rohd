// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_exception.dart
// Definition for exception when an error occurs in the Synthesizer stack.
//
// 2025 June 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when an error occurs in the simulator.
class SynthException extends RohdException {
  /// Constructs a new [Exception] for when an error occurs in the [Synthesizer]
  /// stack.
  SynthException(super.message);
}
