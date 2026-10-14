// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// naming_test_utils.dart
// Shared utilities for testing synthesized signal naming.
//
// 2026 August 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Collects the picked name for every [Logic] in [definition].
Map<Logic, String> collectSynthNames(SynthModuleDefinition definition) {
  final names = <Logic, String>{};
  for (final synthLogic in [
    ...definition.inputs,
    ...definition.outputs,
    ...definition.inOuts,
    ...definition.internalSignals,
  ]) {
    final resolved = synthLogic.resolved;
    final name = resolved.name;
    for (final logic in resolved.logics) {
      names[logic] = name;
    }
  }
  return names;
}
