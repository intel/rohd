// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synth_module_definition.dart
// Definition for SystemCSynthModuleDefinition
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A special [SynthModuleDefinition] for SystemC modules.
class SystemCSynthModuleDefinition extends SynthModuleDefinition {
  /// Creates a new [SystemCSynthModuleDefinition] for the given [module].
  SystemCSynthModuleDefinition(super.module);

  @override
  void process() {
    // For now, do not collapse inline modules. Each InlineSystemVerilog gate
    // remains as a sub-module instantiation and gets emitted as an assign-style
    // expression in the generated SystemC (similar to SV `assign x = a & b`).
    //
    // Future: implement chain-collapsing for compound expressions.
  }

  @override
  SynthSubModuleInstantiation createSubModuleInstantiation(Module m) =>
      SystemCSynthSubModuleInstantiation(m);
}
