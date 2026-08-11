// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_emission_plan.dart
// Backend-neutral structural plans for resolved module emission.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/synth_assignment.dart';
import 'package:rohd/src/synthesizers/utilities/synth_logic.dart';
import 'package:rohd/src/synthesizers/utilities/synth_module_definition.dart';
import 'package:rohd/src/synthesizers/utilities/synth_sub_module_instantiation.dart';

/// Direction of a port in a [ModuleEmissionPlan].
enum ModuleEmissionPortDirection {
  /// An input port.
  input,

  /// An output port.
  output,

  /// A bidirectional port.
  inOut,
}

/// A resolved module port ready for backend-specific declaration rendering.
class ModuleEmissionPortPlan {
  /// Port direction.
  final ModuleEmissionPortDirection direction;

  /// Resolved signal for the port.
  final SynthLogic signal;

  /// Creates a resolved port plan.
  const ModuleEmissionPortPlan(this.direction, this.signal);
}

/// Backend-neutral structural view of a resolved module definition.
///
/// This plan intentionally retains resolved synthesis objects. Backends choose
/// their own declaration syntax, type mapping, and instance lowering while
/// sharing one structural source of truth.
class ModuleEmissionPlan {
  /// The source module.
  final Module sourceModule;

  /// Resolved ports in declaration order.
  final List<ModuleEmissionPortPlan> ports;

  /// Resolved internal signals before backend declaration filtering.
  final List<SynthLogic> internalSignals;

  /// Resolved structural connections.
  final List<SynthAssignment> assignments;

  /// Resolved child module instances.
  ///
  /// Renderers must check [SynthSubModuleInstantiation.needsInstantiation],
  /// since backend lowering may consume an instance while producing output.
  final List<SynthSubModuleInstantiation> instances;

  /// Creates a structural module emission plan.
  const ModuleEmissionPlan({
    required this.sourceModule,
    required this.ports,
    required this.internalSignals,
    required this.assignments,
    required this.instances,
  });

  /// Creates a plan from an already-resolved [definition].
  factory ModuleEmissionPlan.fromDefinition(SynthModuleDefinition definition) =>
      ModuleEmissionPlan(
        sourceModule: definition.module,
        ports: List.unmodifiable([
          for (final signal in definition.inputs)
            ModuleEmissionPortPlan(ModuleEmissionPortDirection.input, signal),
          for (final signal in definition.outputs)
            ModuleEmissionPortPlan(ModuleEmissionPortDirection.output, signal),
          for (final signal in definition.inOuts)
            ModuleEmissionPortPlan(ModuleEmissionPortDirection.inOut, signal),
        ]),
        internalSignals: List.unmodifiable(definition.internalSignals),
        assignments: List.unmodifiable(definition.assignments),
        instances: List.unmodifiable(definition.subModuleInstantiations),
      );

  /// Input ports.
  Iterable<SynthLogic> get inputs => ports
      .where((port) => port.direction == ModuleEmissionPortDirection.input)
      .map((port) => port.signal);

  /// Output ports.
  Iterable<SynthLogic> get outputs => ports
      .where((port) => port.direction == ModuleEmissionPortDirection.output)
      .map((port) => port.signal);

  /// Bidirectional ports.
  Iterable<SynthLogic> get inOuts => ports
      .where((port) => port.direction == ModuleEmissionPortDirection.inOut)
      .map((port) => port.signal);
}
