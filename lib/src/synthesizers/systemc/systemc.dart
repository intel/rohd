// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc.dart
// Definition for SystemC Synthesizer
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesizer_configuration.dart';

export 'systemc_service.dart';
export 'systemc_synthesizer_configuration.dart'
    hide isSystemCHandledInlineModule, systemCUnsupportedReason;

/// A [Synthesizer] which generates a two-state SystemC representation of the
/// given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible,
/// using the same naming strategy as the SystemVerilog synthesizer.
class SystemCSynthesizer extends Synthesizer {
  /// Configuration controlling unsupported SystemC functionality.
  final SystemCSynthesizerConfiguration configuration;

  /// Diagnostics for unsupported module instances emitted as stubs.
  final List<SystemCGenerationDiagnostic> diagnostics = [];

  final Map<Module, bool> _stubDecisions = {};

  /// Creates a SystemC synthesizer with the specified [configuration].
  SystemCSynthesizer({
    this.configuration = const SystemCSynthesizerConfiguration(),
  });

  @override
  bool generatesDefinition(Module module) {
    final reason = systemCUnsupportedReason(module);
    if (reason != null) {
      final allowsStub = _stubDecisions.putIfAbsent(
        module,
        () => configuration.allowsStub(module, reason),
      );
      if (!allowsStub) {
        throw UnsupportedSystemCModuleException(module, reason);
      }
      return true;
    }

    return !isSystemCHandledInlineModule(module);
  }

  @override
  SynthesisResult synthesize(
    Module module,
    String Function(Module module) getInstanceTypeOfModule,
  ) {
    final reason = systemCUnsupportedReason(module);
    if (reason != null) {
      if (!(_stubDecisions[module] ?? false)) {
        throw UnsupportedSystemCModuleException(module, reason);
      }
      diagnostics.add(
        SystemCGenerationDiagnostic(module: module, reason: reason),
      );
      return SystemCStubSynthesisResult(
        module,
        getInstanceTypeOfModule,
        reason: reason,
      );
    }

    return SystemCSynthesisResult(module, getInstanceTypeOfModule);
  }
}
