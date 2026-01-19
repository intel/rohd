// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_utils.dart
// Small helpers for module port lookup used by the schematic tools.
//
// 2025 December 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Convenience extension on `Module` to return a combined view of all
/// declared ports (inputs, outputs, inOuts) keyed by port name, and
/// helpers to lookup port names and port `Logic` objects.
extension ModuleUtils on Module {
  /// Returns a map of all declared ports (inputs, outputs, inOuts)
  /// keyed by port name.
  Map<String, Logic> get ports => {...inputs, ...outputs, ...inOuts};
}
