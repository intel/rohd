// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// passthrough_handler.dart
// Detect pass-through connections and allocate synthetic nets for the
// schematic dumper. API follows ConstantHandler.collectConstants style so
// it can be invoked in the same phase where new net IDs are allocated.
//
// 2025 December 16
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Result of pass-through collection.
class PassThroughResult {
  /// Map of output Logic to input Logic for pass-through connections.
  final Map<Logic, Logic> passThroughConnections;

  /// Map of synthetic net names to their allocated IDs.
  final Map<String, List<Object?>> syntheticNets;

  /// Map of output port names to input port names for pass-throughs.
  final Map<String, String> passThroughNames;

  /// Creates a [PassThroughResult].
  PassThroughResult(
      this.passThroughConnections, this.syntheticNets, this.passThroughNames);
}

/// Handler to detect pass-through connections in a Module and allocate
/// synthetic nets for them.
class PassThroughHandler {
  /// Collects pass-through connections in [module] and allocates synthetic
  /// nets.
  PassThroughResult collectPassThroughs({
    required Module module,
    required dynamic map,
    required Map<Logic, List<Object?>> internalNetIds,
    required Map<String, Object?> ports,
    required List<int> nextIdRef,
  }) {
    final passThroughConnections = <Logic, Logic>{};
    final syntheticNets = <String, List<Object?>>{};

    // Precompute maps for fast lookup:
    // - driverToOutput: direct driver Logic -> output Logic
    // - outputsByLogic: map an output Logic instance to itself for identity
    //   detection when BFS visits the output node directly.
    final driverToOutput = {
      for (final outLogic in module.outputs.values)
        for (final driver in outLogic.srcConnections) driver: outLogic,
    };

    final outputsByLogic = {
      for (final outLogic in module.outputs.values) outLogic: outLogic,
    };

    // Detect pass-through connections by BFS from each input's dsts and
    // checking whether any visited node is a driver of a module output.
    for (final inputEntry in module.inputs.entries) {
      final inputLogic = inputEntry.value;
      final visited = <Logic>{};
      final toVisit = <Logic>[...inputLogic.dstConnections];
      while (toVisit.isNotEmpty) {
        final current = toVisit.removeLast();
        if (visited.add(current)) {
          final out = outputsByLogic[current] ?? driverToOutput[current];
          if (out != null) {
            passThroughConnections[out] = inputLogic;
          }

          // Continue tracing if within module scope
          toVisit.addAll(current.dstConnections.where((dst) =>
              module.signals.contains(dst) ||
              module.outputs.values.contains(dst)));
        }
      }
    }

    // Allocate synthetic net IDs for each pass-through output (a separate
    // net for the module output). Use nextIdRef as mutable reference.
    var nextId = nextIdRef[0];
    for (final outLogic in passThroughConnections.keys) {
      final ids = List<Object?>.generate(outLogic.width, (_) => nextId++);
      final name = 'passthrough_'
          '${outLogic.parentModule?.uniqueInstanceName ?? 'unknown'}_'
          '${outLogic.name}';
      syntheticNets[name] = ids;
      internalNetIds[outLogic] = ids;
    }

    // Build a map of output-name -> input-name for callers that want the
    // original port name pairs instead of Logic objects. This avoids the
    // caller having to reverse-lookup port names by scanning maps.
    // Build a reverse lookup of input Logic -> input name for quick mapping.
    final inputsByLogic = {
      for (final inp in module.inputs.entries) inp.value: inp.key,
    };

    final passThroughNames = {
      for (final e in passThroughConnections.entries)
        e.key.name: (inputsByLogic[e.value] ?? e.value.name),
    };

    nextIdRef[0] = nextId;
    return PassThroughResult(
        passThroughConnections, syntheticNets, passThroughNames);
  }
}
