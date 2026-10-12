// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synthesizer_configuration.dart
// Configuration for SystemC synthesis.
//
// 2026 October
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/always.dart';

/// Selects an unsupported [module] for emission as an empty SystemC stub.
///
/// [reason] describes the SystemC behavior that is unavailable. The predicate
/// may inspect instance properties such as [Module.uniqueInstanceName] to
/// distinguish one instance from other instances of the same type.
typedef SystemCUnsupportedModulePredicate = bool Function(
  Module module,
  String reason,
);

/// Configuration for SystemC synthesis.
class SystemCSynthesizerConfiguration {
  /// Allows every module with explicitly unsupported SystemC behavior to be
  /// emitted as an empty, port-compatible stub.
  ///
  /// Stubbed modules omit behavior and are not logically equivalent to the
  /// source hardware. Unexpected generation and connectivity failures are
  /// still reported.
  final bool stubAllUnsupportedModules;

  /// Selectively allows unsupported modules to be emitted as empty,
  /// port-compatible stubs.
  ///
  /// This predicate is only called for functionality that the SystemC backend
  /// explicitly recognizes as unsupported. It should be deterministic and
  /// free of side effects.
  final SystemCUnsupportedModulePredicate? stubUnsupportedModule;

  /// Creates SystemC synthesis configuration.
  const SystemCSynthesizerConfiguration({
    this.stubAllUnsupportedModules = false,
    this.stubUnsupportedModule,
  });

  /// Whether [module] may be emitted as a stub for [reason].
  bool allowsStub(Module module, String reason) =>
      stubAllUnsupportedModules ||
      (stubUnsupportedModule?.call(module, reason) ?? false);
}

/// Describes behavior omitted from generated SystemC.
class SystemCGenerationDiagnostic {
  /// The module instance whose behavior was omitted.
  final Module module;

  /// Why the backend could not translate the behavior.
  final String reason;

  /// Creates a diagnostic for an unsupported module emitted as a stub.
  const SystemCGenerationDiagnostic({
    required this.module,
    required this.reason,
  });

  /// A human-readable diagnostic message.
  String get message =>
      'SystemC stub "${module.uniqueInstanceName}" (${module.runtimeType}) '
      'omits behavior: $reason';

  @override
  String toString() => message;
}

/// Thrown when required module behavior has no SystemC translation.
class UnsupportedSystemCModuleException extends SynthException {
  /// The unsupported module instance.
  final Module module;

  /// Why the module cannot be translated.
  final String reason;

  /// Creates an unsupported SystemC module exception.
  UnsupportedSystemCModuleException(this.module, this.reason)
      : super(
          'Cannot generate SystemC for instance '
          '"${module.uniqueInstanceName}" (${module.runtimeType}): $reason',
        );
}

/// Whether [module] has a built-in inline/process translation in SystemC.
bool isSystemCHandledInlineModule(Module module) =>
    module is Always ||
    module is FlipFlop ||
    module is SimpleClockGenerator ||
    module is Add ||
    isSystemCSupportedInlineExpression(module);

/// Whether [module] has a built-in SystemC expression translation.
bool isSystemCSupportedInlineExpression(Module module) =>
    module is NotGate ||
    module is And2Gate ||
    module is Or2Gate ||
    module is Xor2Gate ||
    module is Subtract ||
    module is Multiply ||
    module is Divide ||
    module is Modulo ||
    module is Power ||
    module is Equals ||
    module is NotEquals ||
    module is LessThan ||
    module is GreaterThan ||
    module is LessThanOrEqual ||
    module is GreaterThanOrEqual ||
    module is LShift ||
    module is RShift ||
    module is ARShift ||
    module is AndUnary ||
    module is OrUnary ||
    module is XorUnary ||
    module is BusSubset ||
    module is IndexGate ||
    module is Mux ||
    module is ReplicationOp ||
    module is Swizzle;

/// Returns why [module] is explicitly unsupported by SystemC generation.
///
/// A `null` result means the module is either structurally translatable or has
/// a built-in SystemC translation. It does not suppress failures encountered
/// while translating otherwise supported structure.
String? systemCUnsupportedReason(Module module) {
  // Preserve detection for the deprecated customization API until callers
  // migrate to the current SystemVerilog mixin.
  // ignore: deprecated_member_use_from_same_package
  if (module is CustomSystemVerilog) {
    return 'the module provides only a custom SystemVerilog instantiation';
  }

  if (module is! SystemVerilog) {
    return null;
  }

  if (module.generatedDefinitionType == DefinitionGenerationType.custom) {
    return 'the module provides only a custom SystemVerilog definition';
  }

  if (module.generatedDefinitionType == DefinitionGenerationType.none &&
      !isSystemCHandledInlineModule(module)) {
    return module is InlineSystemVerilog
        ? 'the inline SystemVerilog expression has no SystemC translation'
        : 'the SystemVerilog-only leaf has no SystemC translation';
  }

  return null;
}
