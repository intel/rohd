// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_mixins.dart
// SystemC-specific module emission extension contracts.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Allows a module to provide an explicit SystemC expression implementation.
///
/// Use this only when a module cannot be represented by a standard semantic
/// leaf operation. Portable leaf modules should provide semantic leaf metadata
/// instead.
mixin SystemCInlineExpression on Module {
  /// Emits a SystemC/C++ expression for this module's inline result.
  String inlineSystemC(Map<String, String> inputs);
}
