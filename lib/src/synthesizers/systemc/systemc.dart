// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synthesizer.dart
// Definition for SystemC Synthesizer
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';

/// A [Synthesizer] which generates equivalent SystemC as the given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible,
/// using the same naming strategy as the SystemVerilog synthesizer.
class SystemCSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) =>
      // ignore: deprecated_member_use_from_same_package
      !((module is CustomSystemVerilog) ||
          (module is SystemVerilog &&
              module.generatedDefinitionType == DefinitionGenerationType.none));

  @override
  SynthesisResult synthesize(Module module,
          String Function(Module module) getInstanceTypeOfModule) =>
      SystemCSynthesisResult(module, getInstanceTypeOfModule);
}
