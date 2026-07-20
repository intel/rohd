// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inline_leaf_emitter.dart
// Backend renderer contract for inline leaf expressions.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Backend renderer contract for inline leaf expressions.
class InlineLeafEmitter {
  /// Creates an inline leaf emitter contract base.
  const InlineLeafEmitter();

  /// Emits a backend-specific expression for [module] given [inputs].
  String expressionFor(InlineLeaf module, Map<String, String> inputs) {
    throw UnimplementedError(
      'InlineLeafEmitter.expressionFor must be implemented by subclasses.',
    );
  }
}
