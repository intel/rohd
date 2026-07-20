// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inline_leaf.dart
// Backend-neutral contract for inline leaf modules.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Indicates that a [Module] can be rendered as an inline leaf expression by
/// synthesis backends.
mixin InlineLeaf on Module {
  /// The name of the [output] or [inOut] port which can be inlined.
  ///
  /// By default, this assumes one [output] port. Override this for modules
  /// whose inline result is an [inOut] or one of multiple outputs.
  String get resultSignalName {
    if (outputs.keys.length != 1) {
      throw Exception('Inline leaf expected to have exactly one output,'
          ' but saw $outputs.');
    }

    return outputs.keys.first;
  }

  /// Input names that cannot be represented as inline expressions.
  List<String> get expressionlessInputs => const [];

  /// Indicates that this module is only wires, no logic inside, which can be
  /// leveraged for pruning.
  @internal
  bool get isWiresOnly => false;
}
